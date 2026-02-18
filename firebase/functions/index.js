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
const STATE_STALE_RESET_MS = 6 * 60 * 60 * 1000;

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
    eventId: inputEventId,
    uid,
    points,
    checkpoints,
    sessionId: inputSessionId,
    session,
    minLapTimeSeconds,
  } = data;

  const sessionId = inputSessionId || session || null;
  let eventId = inputEventId || null;
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

  const db = admin.firestore();

  // Best-effort event resolution for older clients that still send only raceId + session.
  if (!eventId && sessionId) {
    try {
      const eventsSnap = await db.collection('events').where('track_id', '==', raceId).limit(30).get();
      for (const eventDoc of eventsSnap.docs) {
        const sessions = Array.isArray(eventDoc.data().sessions) ? eventDoc.data().sessions : [];
        const hasSession = sessions.some((s) => s && s.id === sessionId);
        if (hasSession) {
          eventId = eventDoc.id;
          break;
        }
      }
    } catch (resolveError) {
      console.warn('Unable to resolve eventId from sessionId:', resolveError);
    }
  }

  console.log(
    `Received ${points.length} points for race ${raceId} from user ${uid} ` +
      `(event=${eventId || 'n/a'}, session=${sessionId || 'legacy'})`,
  );

  // Legacy race-scoped refs (kept during migration).
  const legacyParticipantRef = db.collection('races').doc(raceId).collection('participants').doc(uid);
  const legacyLapsRef = legacyParticipantRef.collection('laps');
  const legacySessionRef = sessionId ? legacyParticipantRef.collection('sessions').doc(sessionId) : null;
  const legacySessionLapsRef = legacySessionRef ? legacySessionRef.collection('laps') : null;
  const legacyCrossingsRef = legacySessionRef ? legacySessionRef.collection('crossings') : null;
  const legacySummaryRef = legacySessionRef ? legacySessionRef.collection('analysis').doc('summary') : null;
  const legacyStateRef = legacySessionRef ? legacySessionRef.collection('state').doc('current') : null;
  const legacyPassingsRef = db.collection('races').doc(raceId).collection('passings');

  // New event/session-scoped refs (Option 2).
  const eventSessionRef =
    eventId && sessionId
      ? db.collection('events').doc(eventId).collection('sessions').doc(sessionId)
      : null;
  const eventSessionParticipantRef = eventSessionRef ? eventSessionRef.collection('participants').doc(uid) : null;
  const eventSessionLapsRef = eventSessionParticipantRef ? eventSessionParticipantRef.collection('laps') : null;
  const eventCrossingsRef = eventSessionParticipantRef ? eventSessionParticipantRef.collection('crossings') : null;
  const eventStateRef = eventSessionParticipantRef ? eventSessionParticipantRef.collection('state').doc('current') : null;
  const eventSummaryRef = eventSessionRef ? eventSessionRef.collection('analysis').doc('summary') : null;
  const eventPassingsRef = eventSessionRef ? eventSessionRef.collection('passings') : null;

  const passingsRefs = [legacyPassingsRef, eventPassingsRef].filter(Boolean);
  const crossingsRefs = [legacyCrossingsRef, eventCrossingsRef].filter(Boolean);
  const sessionLapsRefs = [legacySessionLapsRef, eventSessionLapsRef].filter(Boolean);
  const summaryRefs = [legacySummaryRef, eventSummaryRef].filter(Boolean);
  const stateRefs = [legacyStateRef, eventStateRef].filter(Boolean);

  let state = null;
  if (eventStateRef) {
    const snap = await eventStateRef.get();
    if (snap.exists) {
      state = snap.data();
    }
  }
  if (!state && legacyStateRef) {
    const snap = await legacyStateRef.get();
    if (snap.exists) {
      state = snap.data();
    }
  }
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

  // Session IDs may be reused across events; reset stale state to avoid
  // inheriting an old open lap into a new session run.
  let firstPointTs = null;
  for (const p of points) {
    if (typeof p.timestamp !== 'number') continue;
    if (firstPointTs === null || p.timestamp < firstPointTs) {
      firstPointTs = p.timestamp;
    }
  }
  if (firstPointTs !== null) {
    const refTs = typeof state.last_crossed_at_ms === 'number'
      ? state.last_crossed_at_ms
      : (typeof state.lap_start_ms === 'number' ? state.lap_start_ms : null);
    if (refTs !== null && firstPointTs - refTs > STATE_STALE_RESET_MS) {
      state = {
        lap_number: 1,
        lap_start_ms: null,
        last_checkpoint_index: -1,
        last_crossed_at_ms: null,
        checkpoint_times: {},
        checkpoint_speeds: {},
      };
      console.log(`Resetting stale lap state for user ${uid} session ${sessionId || 'legacy'}`);
    }
  }

  try {
    if (Array.isArray(checkpoints) && checkpoints.length > 1) {
      const checkpointCount = checkpoints.length;
      const finishCheckpointIndex = checkpointCount - 1;
      const startFinishDistanceM = getDistanceMeters(
        checkpoints[0].lat,
        checkpoints[0].lng,
        checkpoints[finishCheckpointIndex].lat,
        checkpoints[finishCheckpointIndex].lng,
      );
      const startFinishSamePoint = startFinishDistanceM <= CHECKPOINT_DISTANCE_TOLERANCE_M;

      for (let i = 0; i < checkpointCount; i++) {
        const pm = checkpoints[i];
        const nextPm = i < finishCheckpointIndex ? checkpoints[i + 1] : null;

        let bestPP = null;
        let minDist = CHECKPOINT_DISTANCE_TOLERANCE_M;

        for (const pp of points) {
          // If start and finish are the same physical point, the finish crossing
          // must come from a later sample than the lap-opening crossing.
          if (
            startFinishSamePoint &&
            i === finishCheckpointIndex &&
            state.lap_start_ms &&
            pp.timestamp <= state.lap_start_ms + DEDUP_WINDOW_MS
          ) {
            continue;
          }

          const dist = getDistanceMeters(pm.lat, pm.lng, pp.lat, pp.lng);
          if (dist >= minDist) continue;

          // Keep finish checkpoint permissive to ensure lap closure with sparse/noisy data.
          if (i !== finishCheckpointIndex && nextPm) {
            const vTrackLat = nextPm.lat - pm.lat;
            const vTrackLng = nextPm.lng - pm.lng;
            const vPilotLat = pp.lat - pm.lat;
            const vPilotLng = pp.lng - pm.lng;
            const dot = vPilotLat * vTrackLat + vPilotLng * vTrackLng;
            const lenSq = vTrackLat * vTrackLat + vTrackLng * vTrackLng;
            if (dot < 0 || dot > lenSq) continue;
          }

          minDist = dist;
          bestPP = pp;
        }

        if (!bestPP) continue;
        const openingOnSharedLine =
          startFinishSamePoint &&
          i === finishCheckpointIndex &&
          !state.lap_start_ms;
        const checkpointIndex = openingOnSharedLine ? 0 : i;

        // Dedup and order control
        const sameCheckpoint = state.last_checkpoint_index === checkpointIndex;
        const tooSoon =
          state.last_crossed_at_ms &&
          bestPP.timestamp - state.last_crossed_at_ms < DEDUP_WINDOW_MS &&
          sameCheckpoint;
        const wrappedStart =
          state.last_checkpoint_index === finishCheckpointIndex && checkpointIndex === 0;
        const outOfOrder =
          !wrappedStart &&
          checkpointIndex !== finishCheckpointIndex &&
          state.last_checkpoint_index > checkpointIndex;
        if (tooSoon || outOfOrder) {
          continue;
        }

        const ignoreFinishAtLapOpen =
          startFinishSamePoint &&
          i === finishCheckpointIndex &&
          state.lap_start_ms &&
          bestPP.timestamp - state.lap_start_ms < minLapMs;
        if (ignoreFinishAtLapOpen) {
          // Start and finish share the same physical point; avoid closing
          // immediately after opening while still near the line.
          continue;
        }

        const lapNumber = state.lap_number || 1;
        const prevTs = state.checkpoint_times ? state.checkpoint_times[checkpointIndex - 1] : null;
        const lapStartTs = state.lap_start_ms;
        const sectorTime = prevTs ? bestPP.timestamp - prevTs : null;
        const splitTime = lapStartTs ? bestPP.timestamp - lapStartTs : null;

        if (crossingsRefs.length) {
          const crossingPayload = {
            lap_number: lapNumber,
            checkpoint_index: checkpointIndex,
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
          };
          await Promise.all(crossingsRefs.map((ref) => ref.add(crossingPayload)));
        }

        const passingPayload = {
          participant_uid: uid,
          lap_number: lapNumber,
          lap_time: null,
          timestamp: admin.firestore.Timestamp.fromMillis(bestPP.timestamp),
          session_id: sessionId || null,
          event_id: eventId || null,
          race_id: raceId,
          checkpoint_index: checkpointIndex,
          flags: [],
          sector_time: sectorTime,
          split_time: splitTime,
          trap_speed: bestPP.speed,
        };
        await Promise.all(passingsRefs.map((ref) => ref.add(passingPayload)));

        // Update state
        state.last_checkpoint_index = checkpointIndex;
        state.last_crossed_at_ms = bestPP.timestamp;
        state.checkpoint_times = state.checkpoint_times || {};
        state.checkpoint_speeds = state.checkpoint_speeds || {};
        state.checkpoint_times[checkpointIndex] = bestPP.timestamp;
        state.checkpoint_speeds[checkpointIndex] = bestPP.speed;

        // Start timing on first checkpoint
        if (checkpointIndex === 0 && !state.lap_start_ms) {
          state.lap_start_ms = bestPP.timestamp;
        }

        // Close lap on finish checkpoint (last checkpoint)
        if (i === finishCheckpointIndex && state.lap_start_ms && !openingOnSharedLine) {
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

          if (sessionLapsRefs.length) {
            await Promise.all(
              sessionLapsRefs.map((ref) => ref.doc(lapDocId).set(lapPayload, { merge: true })),
            );
          }
          if (summaryRefs.length) {
            await Promise.all(summaryRefs.map((ref) => updateSummary(ref, lapPayload)));
          }

          await legacyLapsRef.doc(lapDocId).set(
            {
              ...lapPayload,
              session_id: sessionId || null,
              event_id: eventId || null,
            },
            { merge: true },
          );

          // Passings record with lap_time for finish line
          const closingPassingPayload = {
            participant_uid: uid,
            lap_number: lapNumber,
            lap_time: totalLapTimeMs,
            timestamp: admin.firestore.Timestamp.fromMillis(lapEnd),
            session_id: sessionId || null,
            event_id: eventId || null,
            race_id: raceId,
            checkpoint_index: finishCheckpointIndex,
            flags: [],
            sector_time: sectors_ms[sectors_ms.length - 1] || null,
            split_time: splits_ms[splits_ms.length - 1] || null,
            trap_speed: bestPP.speed,
            valid,
          };
          await Promise.all(passingsRefs.map((ref) => ref.add(closingPassingPayload)));

          const nextLapNumber = lapNumber + 1;
          if (startFinishSamePoint) {
            // In start/finish tracks, closing a lap also opens the next lap on
            // the same line crossing.
            const autoOpenPayload = {
              participant_uid: uid,
              lap_number: nextLapNumber,
              lap_time: null,
              timestamp: admin.firestore.Timestamp.fromMillis(lapEnd),
              session_id: sessionId || null,
              event_id: eventId || null,
              race_id: raceId,
              checkpoint_index: 0,
              flags: ['auto_open'],
              sector_time: null,
              split_time: 0,
              trap_speed: bestPP.speed,
            };
            await Promise.all(passingsRefs.map((ref) => ref.add(autoOpenPayload)));

            state.lap_number = nextLapNumber;
            state.lap_start_ms = lapEnd;
            state.last_checkpoint_index = 0;
            state.last_crossed_at_ms = lapEnd;
            state.checkpoint_times = { 0: lapEnd };
            state.checkpoint_speeds = { 0: bestPP.speed };
          } else {
            // Non start/finish tracks open next lap only when checkpoint 0 is crossed.
            state.lap_number = nextLapNumber;
            state.lap_start_ms = null;
            state.last_checkpoint_index = finishCheckpointIndex;
            state.last_crossed_at_ms = lapEnd;
            state.checkpoint_times = {};
            state.checkpoint_speeds = {};
          }
        } else if (i === 0 && !state.lap_start_ms) {
          // keep compatibility branch (never hit due condition above)
          state.lap_start_ms = bestPP.timestamp;
        }

        if (stateRefs.length) {
          await Promise.all(stateRefs.map((ref) => ref.set(state, { merge: true })));
        }
      }
    }
  } catch (e) {
    console.error('Error in ingestTelemetry algorithm:', e);
  }

  // Publish to Pub/Sub for async processing / BigQuery
  const messagePayload = {
    raceId,
    eventId,
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
  const { raceId, eventId, uid, sessionId, points, ingestedAt } = payload;

  console.log(
    `Processing batch for race: ${raceId}, event: ${eventId || 'n/a'}, ` +
      `user: ${uid}, session: ${sessionId || 'legacy'}`,
  );

  const tasks = [];
  const db = admin.firestore();
  const participantRef = db.collection('races').doc(raceId).collection('participants').doc(uid);
  const eventSessionParticipantRef =
    eventId && sessionId
      ? db.collection('events').doc(eventId).collection('sessions').doc(sessionId).collection('participants').doc(uid)
      : null;

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

    if (eventSessionParticipantRef) {
      const eventStateRef = eventSessionParticipantRef.collection('state').doc('current');
      tasks.push(
        eventSessionParticipantRef.set(
          {
            current: realtime,
            last_updated: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        ),
      );
      tasks.push(
        eventStateRef.set(
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
    eventId: eventId || null,
    uid,
    sessionId: sessionId || null,
  }));
  if (enrichedPoints.length) {
    tasks.push(
      bigquery
        .dataset('telemetry')
        .table('raw_points')
        .insert(enrichedPoints)
        .catch((error) => {
          // Do not fail realtime/session writes when BigQuery rejects a row batch.
          console.error('BigQuery insert failed:', error);
        }),
    );
  }

  await Promise.all(tasks);
});
