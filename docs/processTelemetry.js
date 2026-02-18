const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { PubSub } = require('@google-cloud/pubsub');
const { BigQuery } = require('@google-cloud/bigquery');

admin.initializeApp();

const pubsub = new PubSub();
const TOPIC_NAME = 'telemetry-topic';

// Tunables for lap detection/validation
const DEFAULT_MIN_LAP_TIME_SECONDS = 15;
const DEDUP_WINDOW_MS = 400; // ignore checkpoint repeats inside this window
const CHECKPOINT_DISTANCE_TOLERANCE_M = 40;

function getDistanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371e3; // metres
  const phi1 = (lat1 * Math.PI) / 180;
  const phi2 = (lat2 * Math.PI) / 180;
  const dPhi = ((lat2 - lat1) * Math.PI) / 180;
  const dLambda = ((lon2 - lon1) * Math.PI) / 180;

  const a =
    Math.sin(dPhi / 2) * Math.sin(dPhi / 2) +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) * Math.sin(dLambda / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function computeSpeedStats(speeds = []) {
  if (!speeds.length) return null;
  const min = Math.min(...speeds);
  const max = Math.max(...speeds);
  const avg = speeds.reduce((sum, v) => sum + v, 0) / speeds.length;
  return { min_mps: min, max_mps: max, avg_mps: avg };
}

async function updateSummary(summaryRef, lapData) {
  if (!summaryRef || !lapData.valid) return;

  const snap = await summaryRef.get();
  const current = snap.exists ? snap.data() : {};

  const updated = { ...current };
  updated.total_laps_count = (current.total_laps_count || 0) + 1;
  updated.valid_laps_count = (current.valid_laps_count || 0) + 1;

  if (!current.best_lap_ms || lapData.total_lap_time_ms < current.best_lap_ms) {
    updated.best_lap_ms = lapData.total_lap_time_ms;
  }

  const bestSectors = current.best_sectors_ms || [];
  const sectors = lapData.sectors_ms || [];
  const mergedSectors = [];
  const maxLen = Math.max(bestSectors.length, sectors.length);
  for (let i = 0; i < maxLen; i++) {
    const candidates = [];
    if (typeof bestSectors[i] === 'number') candidates.push(bestSectors[i]);
    if (typeof sectors[i] === 'number') candidates.push(sectors[i]);
    if (candidates.length) {
      mergedSectors[i] = Math.min(...candidates);
    }
  }
  if (mergedSectors.length) {
    updated.best_sectors_ms = mergedSectors;
    updated.optimal_lap_ms = mergedSectors.reduce((sum, v) => sum + v, 0);
  }

  updated.updated_at = admin.firestore.FieldValue.serverTimestamp();
  await summaryRef.set(updated, { merge: true });
}

exports.ingestTelemetry = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in to send telemetry.');
  }

  const {
    raceId,
    uid,
    points,
    checkpoints,
    sessionId: inputSessionId,
    session,
    minLapTimeSeconds,
  } = data;

  const sessionId = inputSessionId || session || null;
  const minLapMs = (minLapTimeSeconds || DEFAULT_MIN_LAP_TIME_SECONDS) * 1000;

  if (!raceId || !uid) {
    throw new functions.https.HttpsError('invalid-argument', 'raceId and uid are required.');
  }
  if (!points || !Array.isArray(points)) {
    throw new functions.https.HttpsError('invalid-argument', 'Points must be an array.');
  }
  if (!points.length) {
    return { success: true, count: 0 };
  }

  console.log(`Received ${points.length} points for race ${raceId} from user ${uid} (session=${sessionId || 'legacy'})`);

  const db = admin.firestore();
  const participantRef = db.collection('races').doc(raceId).collection('participants').doc(uid);
  const lapsRef = participantRef.collection('laps'); // legacy compatibility

  const sessionRef = sessionId ? participantRef.collection('sessions').doc(sessionId) : null;
  const sessionLapsRef = sessionRef ? sessionRef.collection('laps') : null;
  const crossingsRef = sessionRef ? sessionRef.collection('crossings') : null;
  const summaryRef = sessionRef ? sessionRef.collection('analysis').doc('summary') : null;
  const stateRef = sessionRef ? sessionRef.collection('state').doc('current') : null;
  const passingsRef = db.collection('races').doc(raceId).collection('passings');

  let state = stateRef ? (await stateRef.get()).data() : null;
  if (!state) {
    state = {
      lap_number: 1,
      lap_start_ms: null,
      last_checkpoint_index: -1,
      last_crossed_at_ms: null,
      checkpoint_times: {},
      checkpoint_speeds: {},
    };
  }

  try {
    if (Array.isArray(checkpoints) && checkpoints.length > 1) {
      for (let i = 0; i < checkpoints.length - 1; i++) {
        const pm = checkpoints[i];
        const nextPm = checkpoints[(i + 1) % checkpoints.length];

        let bestPP = null;
        let minDist = CHECKPOINT_DISTANCE_TOLERANCE_M;

        for (const pp of points) {
          const dist = getDistanceMeters(pm.lat, pm.lng, pp.lat, pp.lng);
          if (dist >= minDist) continue;

          // Direction check: PP must be ahead of PM towards next PM
          const vTrackLat = nextPm.lat - pm.lat;
          const vTrackLng = nextPm.lng - pm.lng;
          const vPilotLat = pp.lat - pm.lat;
          const vPilotLng = pp.lng - pm.lng;
          const dot = vPilotLat * vTrackLat + vPilotLng * vTrackLng;
          const lenSq = vTrackLat * vTrackLat + vTrackLng * vTrackLng;
          if (dot < 0 || dot > lenSq) continue;

          minDist = dist;
          bestPP = pp;
        }

        if (!bestPP) continue;

        // Dedup and order control
        const sameCheckpoint = state.last_checkpoint_index === i;
        const tooSoon =
          state.last_crossed_at_ms &&
          bestPP.timestamp - state.last_crossed_at_ms < DEDUP_WINDOW_MS &&
          sameCheckpoint;
        const outOfOrder = i !== 0 && state.last_checkpoint_index > i;
        if (tooSoon || outOfOrder) {
          continue;
        }

        const lapNumber = state.lap_number || 1;
        const prevTs = state.checkpoint_times ? state.checkpoint_times[i - 1] : null;
        const lapStartTs = state.lap_start_ms;
        const sectorTime = prevTs ? bestPP.timestamp - prevTs : null;
        const splitTime = lapStartTs ? bestPP.timestamp - lapStartTs : null;

        if (crossingsRef) {
          await crossingsRef.add({
            lap_number: lapNumber,
            checkpoint_index: i,
            crossed_at_ms: bestPP.timestamp,
            speed_mps: bestPP.speed,
            lat: bestPP.lat,
            lng: bestPP.lng,
            sector_time_ms: sectorTime,
            split_time_ms: splitTime,
            method: 'nearest_point',
            distance_to_checkpoint_m: minDist,
            confidence: 0.9,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        await passingsRef.add({
          participant_uid: uid,
          lap_number: lapNumber,
          lap_time: null,
          timestamp: admin.firestore.Timestamp.fromMillis(bestPP.timestamp),
          session_id: sessionId || null,
          checkpoint_index: i,
          flags: [],
          sector_time: sectorTime,
          split_time: splitTime,
          trap_speed: bestPP.speed,
        });

        // Update state
        state.last_checkpoint_index = i;
        state.last_crossed_at_ms = bestPP.timestamp;
        state.checkpoint_times = state.checkpoint_times || {};
        state.checkpoint_speeds = state.checkpoint_speeds || {};
        state.checkpoint_times[i] = bestPP.timestamp;
        state.checkpoint_speeds[i] = bestPP.speed;

        // Handle cp_0: close current lap and open next one
        if (i === 0) {
          if (!state.lap_start_ms) {
            state.lap_start_ms = bestPP.timestamp;
          } else {
            const lapStart = state.lap_start_ms;
            const lapEnd = bestPP.timestamp;
            const totalLapTimeMs = lapEnd - lapStart;
            const valid = totalLapTimeMs >= minLapMs;
            const invalidReasons = valid ? [] : [`min_lap_time_seconds_${minLapTimeSeconds || DEFAULT_MIN_LAP_TIME_SECONDS}`];

            const checkpointIndices = Object.keys(state.checkpoint_times || {})
              .map(Number)
              .sort((a, b) => a - b);

            const splits_ms = [];
            const sectors_ms = [];
            const trap_speeds_mps = [];
            let previousTs = lapStart;

            checkpointIndices.forEach((idx) => {
              const cpTs = state.checkpoint_times[idx];
              splits_ms.push(cpTs - lapStart);
              if (idx !== 0) {
                sectors_ms.push(cpTs - previousTs);
              }
              previousTs = cpTs;
              if (typeof state.checkpoint_speeds[idx] === 'number') {
                trap_speeds_mps.push(state.checkpoint_speeds[idx]);
              }
            });

            const lapDocId = `lap_${lapNumber}`;
            const lapPayload = {
              number: lapNumber,
              lap_start_ms: lapStart,
              lap_end_ms: lapEnd,
              total_lap_time_ms: totalLapTimeMs,
              splits_ms,
              sectors_ms,
              trap_speeds_mps,
              speed_stats: computeSpeedStats(trap_speeds_mps),
              valid,
              invalid_reasons: invalidReasons,
              created_at: admin.firestore.FieldValue.serverTimestamp(),
            };

            if (sessionLapsRef) {
              await sessionLapsRef.doc(lapDocId).set(lapPayload, { merge: true });
              await updateSummary(summaryRef, lapPayload);
            }

            await lapsRef.doc(lapDocId).set(
              {
                ...lapPayload,
                session_id: sessionId || null,
              },
              { merge: true },
            );

            // Passings record with lap_time for finish line
            await passingsRef.add({
              participant_uid: uid,
              lap_number: lapNumber,
              lap_time: totalLapTimeMs,
              timestamp: admin.firestore.Timestamp.fromMillis(lapEnd),
              session_id: sessionId || null,
              checkpoint_index: 0,
              flags: [],
              sector_time: sectors_ms[sectors_ms.length - 1] || null,
              split_time: splits_ms[splits_ms.length - 1] || null,
              trap_speed: bestPP.speed,
              valid,
            });

            // Reset state for next lap
            state.lap_number = lapNumber + 1;
            state.lap_start_ms = lapEnd;
            state.last_checkpoint_index = 0;
            state.last_crossed_at_ms = lapEnd;
            state.checkpoint_times = { 0: lapEnd };
            state.checkpoint_speeds = { 0: bestPP.speed };
          }
        }

        if (stateRef) {
          await stateRef.set(state, { merge: true });
        }
      }
    }
  } catch (e) {
    console.error('Error in ingestTelemetry algorithm:', e);
  }

  // Publish to Pub/Sub for async processing / BigQuery
  const messagePayload = {
    raceId,
    uid,
    sessionId,
    checkpoints,
    points,
    ingestedAt: Date.now(),
    userEmail: context.auth.token.email || null,
  };

  const dataBuffer = Buffer.from(JSON.stringify(messagePayload));

  try {
    const topic = pubsub.topic(TOPIC_NAME);
    const messageId = await topic.publishMessage({ data: dataBuffer });
    console.log(`Message ${messageId} published.`);

    return { success: true, messageId };
  } catch (error) {
    console.error('Processing Error:', error);
    throw new functions.https.HttpsError('internal', 'Failed to process telemetry.');
  }
});

exports.processTelemetry = functions.pubsub.topic(TOPIC_NAME).onPublish(async (message) => {
  const payload = message.json;
  const { raceId, uid, sessionId, points, ingestedAt } = payload;

  console.log(`Processing batch for race: ${raceId}, user: ${uid}, session: ${sessionId || 'legacy'}`);

  const tasks = [];
  const db = admin.firestore();
  const participantRef = db.collection('races').doc(raceId).collection('participants').doc(uid);

  if (points && points.length > 0) {
    const lastPoint = points[points.length - 1];
    const realtime = {
      lat: lastPoint.lat,
      lng: lastPoint.lng,
      speed: lastPoint.speed,
      heading: lastPoint.heading,
      altitude: lastPoint.altitude || 0,
      timestamp: lastPoint.timestamp,
      ingested_at: ingestedAt || Date.now(),
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
    };

    tasks.push(
      participantRef.set(
        {
          current: realtime,
        },
        { merge: true },
      ),
    );

    if (sessionId) {
      const sessionStateRef = participantRef.collection('sessions').doc(sessionId).collection('state').doc('current');
      tasks.push(
        sessionStateRef.set(
          {
            current: realtime,
          },
          { merge: true },
        ),
      );
    }
  }

  const bigquery = new BigQuery();
  const enrichedPoints = (points || []).map((p) => ({
    ...p,
    raceId,
    uid,
    sessionId: sessionId || null,
  }));
  if (enrichedPoints.length) {
    tasks.push(bigquery.dataset('telemetry').table('raw_points').insert(enrichedPoints));
  }

  await Promise.all(tasks);
});
