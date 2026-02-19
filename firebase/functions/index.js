const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { PubSub } = require('@google-cloud/pubsub');
const { BigQuery } = require('@google-cloud/bigquery');
const {
  DEFAULT_DEDUP_WINDOW_MS,
  DEFAULT_MIN_LAP_TIME_SECONDS,
  shouldSkipCheckpointCrossing,
  buildLapPayloadFromState,
  buildLapPayloadFromPassings,
  buildSessionSummaryFromLaps,
  toMillis,
} = require('./lap_analysis_utils');

admin.initializeApp();

const pubsub = new PubSub();
const TOPIC_NAME = 'telemetry-topic';

// Tunables for lap detection/validation
const DEDUP_WINDOW_MS = DEFAULT_DEDUP_WINDOW_MS; // ignore checkpoint repeats inside this window
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

function normalizeCheckpoint(rawCheckpoint) {
  if (!rawCheckpoint || typeof rawCheckpoint !== 'object') return null;
  const lat = Number(rawCheckpoint.lat);
  const lng = Number(rawCheckpoint.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

function normalizeCheckpointIndex(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
  }
  return null;
}

function normalizeTimelineType(value) {
  const normalized = (value || '').toString().trim().toLowerCase();
  if (
    normalized === 'start_finish' ||
    normalized === 'startfinish' ||
    normalized === 'start-finish' ||
    normalized === 'sf'
  ) {
    return 'start_finish';
  }
  if (normalized === 'trap') return 'trap';
  return 'split';
}

function resolveEffectiveCheckpoints(rawCheckpoints, rawTimelines) {
  if (!Array.isArray(rawCheckpoints)) return [];
  const checkpoints = rawCheckpoints
    .map((cp) => normalizeCheckpoint(cp))
    .filter(Boolean);
  if (checkpoints.length < 2) return checkpoints;

  if (!Array.isArray(rawTimelines) || !rawTimelines.length) {
    return checkpoints;
  }

  const timelines = rawTimelines
    .map((timeline, idx) => {
      if (!timeline || typeof timeline !== 'object') return null;
      const checkpointIndex = normalizeCheckpointIndex(
        timeline.checkpoint_index ?? timeline.checkpointIndex ?? timeline.checkpoint,
      );
      if (checkpointIndex === null) return null;
      const order = normalizeCheckpointIndex(timeline.order) ?? idx;
      const enabled = timeline.enabled !== false;
      return {
        type: normalizeTimelineType(timeline.type),
        checkpointIndex,
        order,
        enabled,
      };
    })
    .filter(Boolean)
    .filter((timeline) => timeline.enabled)
    .sort((a, b) => a.order - b.order);

  if (!timelines.length) return checkpoints;

  const startTimeline = timelines.find((timeline) => timeline.type === 'start_finish');
  const startIdx =
    startTimeline && startTimeline.checkpointIndex >= 0 && startTimeline.checkpointIndex < checkpoints.length
      ? startTimeline.checkpointIndex
      : 0;

  const originalFinishIdx = checkpoints.length - 1;
  const originalStart = checkpoints[0];
  const originalFinish = checkpoints[originalFinishIdx];
  const trackIsClosed =
    getDistanceMeters(
      originalStart.lat,
      originalStart.lng,
      originalFinish.lat,
      originalFinish.lng,
    ) <= CHECKPOINT_DISTANCE_TOLERANCE_M;

  const finishIdx = trackIsClosed ? startIdx : originalFinishIdx;
  const usedIndices = new Set([startIdx, finishIdx]);
  const intermediatePoints = [];

  for (const timeline of timelines) {
    if (timeline.type === 'start_finish') continue;
    const idx = timeline.checkpointIndex;
    if (idx < 0 || idx >= checkpoints.length) continue;
    if (usedIndices.has(idx)) continue;
    usedIndices.add(idx);
    intermediatePoints.push(checkpoints[idx]);
  }

  // Backward compatibility: if no timeline-selected intermediates are present,
  // keep legacy checkpoint sequence from the track definition.
  if (!intermediatePoints.length && startIdx === 0 && finishIdx === originalFinishIdx) {
    for (let i = 1; i < originalFinishIdx; i++) {
      intermediatePoints.push(checkpoints[i]);
    }
  }

  const effective = [checkpoints[startIdx], ...intermediatePoints, checkpoints[finishIdx]].filter(Boolean);
  if (effective.length < 2) return checkpoints;
  return effective;
}

async function updateSummary(summaryRef, lapData) {
  if (!summaryRef || !lapData || !lapData.valid) return;
  const lapTimeMs =
    typeof lapData.total_lap_time_ms === 'number' ? lapData.total_lap_time_ms : null;
  if (lapTimeMs === null || lapTimeMs <= 0) return;

  const snap = await summaryRef.get();
  const current = snap.exists ? snap.data() : {};

  const updated = { ...current };
  updated.total_laps_count = (current.total_laps_count || 0) + 1;
  updated.valid_laps_count = (current.valid_laps_count || 0) + 1;

  if (!current.best_lap_ms || lapTimeMs < current.best_lap_ms) {
    updated.best_lap_ms = lapTimeMs;
  }

  const bestSectors = Array.isArray(current.best_sectors_ms) ? current.best_sectors_ms : [];
  const sectors = Array.isArray(lapData.sectors_ms) ? lapData.sectors_ms : [];
  const mergedSectors = [];
  const maxLen = Math.max(bestSectors.length, sectors.length);
  for (let i = 0; i < maxLen; i++) {
    const candidates = [];
    if (typeof bestSectors[i] === 'number' && bestSectors[i] > 0) {
      candidates.push(bestSectors[i]);
    }
    if (typeof sectors[i] === 'number' && sectors[i] > 0) {
      candidates.push(sectors[i]);
    }
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

function asFiniteNumber(value, fallback = null) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return parsed;
}

async function commitSetOperations(db, operations, chunkSize = 400) {
  if (!Array.isArray(operations) || !operations.length) return;
  for (let i = 0; i < operations.length; i += chunkSize) {
    const batch = db.batch();
    const chunk = operations.slice(i, i + chunkSize);
    for (const op of chunk) {
      if (!op || !op.ref) continue;
      if (op.options) {
        batch.set(op.ref, op.data, op.options);
      } else {
        batch.set(op.ref, op.data);
      }
    }
    await batch.commit();
  }
}

async function resolveMinLapTimeSeconds(db, eventId, sessionId, fallbackSeconds) {
  if (!eventId || !sessionId) return fallbackSeconds;
  try {
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists || !eventDoc.data()) return fallbackSeconds;
    const sessions = Array.isArray(eventDoc.data().sessions) ? eventDoc.data().sessions : [];
    const sessionEntry = sessions.find((entry) => entry && entry.id === sessionId);
    if (!sessionEntry) return fallbackSeconds;
    const parsed = asFiniteNumber(sessionEntry.min_lap_time_seconds, fallbackSeconds);
    return parsed !== null ? Math.max(0, Math.trunc(parsed)) : fallbackSeconds;
  } catch (error) {
    console.warn('resolveMinLapTimeSeconds failed:', error);
    return fallbackSeconds;
  }
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
    timelines,
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
  const effectiveCheckpoints = resolveEffectiveCheckpoints(checkpoints, timelines);

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
      `(event=${eventId || 'n/a'}, session=${sessionId || 'legacy'}, ` +
      `checkpoints=${effectiveCheckpoints.length}, timelines=${Array.isArray(timelines) ? timelines.length : 0})`,
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
    if (Array.isArray(effectiveCheckpoints) && effectiveCheckpoints.length > 1) {
      const checkpointCount = effectiveCheckpoints.length;
      const finishCheckpointIndex = checkpointCount - 1;
      const startFinishDistanceM = getDistanceMeters(
        effectiveCheckpoints[0].lat,
        effectiveCheckpoints[0].lng,
        effectiveCheckpoints[finishCheckpointIndex].lat,
        effectiveCheckpoints[finishCheckpointIndex].lng,
      );
      const startFinishSamePoint = startFinishDistanceM <= CHECKPOINT_DISTANCE_TOLERANCE_M;

      for (let i = 0; i < checkpointCount; i++) {
        const pm = effectiveCheckpoints[i];
        const nextPm = i < finishCheckpointIndex ? effectiveCheckpoints[i + 1] : null;

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

        // Dedup and checkpoint order control.
        const shouldSkip = shouldSkipCheckpointCrossing({
          lastCheckpointIndex: state.last_checkpoint_index,
          checkpointIndex,
          lastCrossedAtMs: state.last_crossed_at_ms,
          crossedAtMs: bestPP.timestamp,
          finishCheckpointIndex,
          dedupWindowMs: DEDUP_WINDOW_MS,
        });
        if (shouldSkip) {
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
          const lapPayloadBase = buildLapPayloadFromState({
            lapNumber,
            lapStartMs: lapStart,
            lapEndMs: lapEnd,
            checkpointTimes: state.checkpoint_times,
            checkpointSpeeds: state.checkpoint_speeds,
            minLapMs,
            minLapTimeSeconds: minLapTimeSeconds || DEFAULT_MIN_LAP_TIME_SECONDS,
          });
          if (!lapPayloadBase) {
            continue;
          }

          const lapDocId = `lap_${lapNumber}`;
          const lapPayload = {
            ...lapPayloadBase,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          };
          const totalLapTimeMs = lapPayload.total_lap_time_ms;
          const valid = lapPayload.valid;

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
            sector_time:
              lapPayload.sectors_ms[lapPayload.sectors_ms.length - 1] || null,
            split_time:
              lapPayload.splits_ms[lapPayload.splits_ms.length - 1] || null,
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
    checkpoints: effectiveCheckpoints,
    timelines: Array.isArray(timelines) ? timelines : null,
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

exports.backfillSessionAnalytics = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required to run backfill.',
    );
  }

  const role = (context.auth.token.role || '').toString().trim().toLowerCase();
  const isAdmin =
    context.auth.token.admin === true || role === 'admin' || role === 'root';
  if (!isAdmin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only administrators can run backfill.',
    );
  }

  const raceId = (data.raceId || '').toString().trim();
  const sessionId = (data.sessionId || '').toString().trim();
  const eventId = (data.eventId || '').toString().trim() || null;
  if (!raceId || !sessionId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'raceId and sessionId are required.',
    );
  }

  const participantLimitRaw = asFiniteNumber(data.participantLimit, 250);
  const participantLimit = Math.min(
    500,
    Math.max(1, Math.trunc(participantLimitRaw || 250)),
  );
  const requestedMinLap = asFiniteNumber(data.minLapTimeSeconds, null);

  const db = admin.firestore();
  const minLapTimeSeconds = await resolveMinLapTimeSeconds(
    db,
    eventId,
    sessionId,
    requestedMinLap !== null
      ? Math.max(0, Math.trunc(requestedMinLap))
      : DEFAULT_MIN_LAP_TIME_SECONDS,
  );
  const minLapMs = minLapTimeSeconds * 1000;

  const participantsSnap = await db
    .collection('races')
    .doc(raceId)
    .collection('participants')
    .limit(participantLimit)
    .get();

  const result = {
    raceId,
    eventId,
    sessionId,
    minLapTimeSeconds,
    participantsScanned: participantsSnap.size,
    participantsUpdated: 0,
    lapsRebuilt: 0,
    crossingsRebuilt: 0,
  };

  for (const participantDoc of participantsSnap.docs) {
    const uid = participantDoc.id;
    const passingsRaw = [];

    if (eventId) {
      const eventPassingsSnap = await db
        .collection('events')
        .doc(eventId)
        .collection('sessions')
        .doc(sessionId)
        .collection('passings')
        .where('participant_uid', '==', uid)
        .limit(6000)
        .get();
      for (const doc of eventPassingsSnap.docs) {
        passingsRaw.push({ id: doc.id, ...doc.data() });
      }
    }

    if (!passingsRaw.length) {
      const legacyPassingsSnap = await db
        .collection('races')
        .doc(raceId)
        .collection('passings')
        .where('participant_uid', '==', uid)
        .limit(10000)
        .get();
      for (const doc of legacyPassingsSnap.docs) {
        passingsRaw.push({ id: doc.id, ...doc.data() });
      }
    }

    const passings = passingsRaw
      .filter((passing) => {
        const passingSessionId = (passing.session_id || '').toString().trim();
        return passingSessionId === sessionId;
      })
      .sort((a, b) => {
        const at = toMillis(a.timestamp) || 0;
        const bt = toMillis(b.timestamp) || 0;
        return at - bt;
      });

    if (!passings.length) {
      continue;
    }

    const passingsByLap = new Map();
    for (const passing of passings) {
      const lapNumber = asFiniteNumber(passing.lap_number, null);
      if (lapNumber === null || lapNumber <= 0) continue;
      const normalizedLapNumber = Math.trunc(lapNumber);
      if (!passingsByLap.has(normalizedLapNumber)) {
        passingsByLap.set(normalizedLapNumber, []);
      }
      passingsByLap.get(normalizedLapNumber).push(passing);
    }

    if (!passingsByLap.size) {
      continue;
    }

    const raceParticipantRef = db.collection('races').doc(raceId).collection('participants').doc(uid);
    const raceSessionRef = raceParticipantRef.collection('sessions').doc(sessionId);
    const raceSessionLapsRef = raceSessionRef.collection('laps');
    const raceSessionCrossingsRef = raceSessionRef.collection('crossings');
    const raceSessionSummaryRef = raceSessionRef.collection('analysis').doc('summary');

    const eventSessionParticipantRef = eventId
      ? db
        .collection('events')
        .doc(eventId)
        .collection('sessions')
        .doc(sessionId)
        .collection('participants')
        .doc(uid)
      : null;
    const eventSessionLapsRef = eventSessionParticipantRef
      ? eventSessionParticipantRef.collection('laps')
      : null;
    const eventSessionCrossingsRef = eventSessionParticipantRef
      ? eventSessionParticipantRef.collection('crossings')
      : null;
    const eventSummaryRef = eventId
      ? db
        .collection('events')
        .doc(eventId)
        .collection('sessions')
        .doc(sessionId)
        .collection('analysis')
        .doc('summary')
      : null;

    const writeOps = [];
    const rebuiltLaps = [];

    const sortedLapNumbers = [...passingsByLap.keys()].sort((a, b) => a - b);
    for (const lapNumber of sortedLapNumbers) {
      const lapPassings = passingsByLap.get(lapNumber) || [];
      const lapPayloadBase = buildLapPayloadFromPassings({
        lapNumber,
        passings: lapPassings,
        minLapMs,
        minLapTimeSeconds,
      });
      if (!lapPayloadBase) continue;

      const lapDocId = `lap_${lapNumber}`;
      const lapPayload = {
        ...lapPayloadBase,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        backfilled_from_passings: true,
      };
      rebuiltLaps.push(lapPayloadBase);
      result.lapsRebuilt += 1;

      writeOps.push({
        ref: raceSessionLapsRef.doc(lapDocId),
        data: lapPayload,
        options: { merge: true },
      });
      writeOps.push({
        ref: raceParticipantRef.collection('laps').doc(lapDocId),
        data: {
          ...lapPayload,
          session_id: sessionId,
          event_id: eventId || null,
        },
        options: { merge: true },
      });

      if (eventSessionLapsRef) {
        writeOps.push({
          ref: eventSessionLapsRef.doc(lapDocId),
          data: lapPayload,
          options: { merge: true },
        });
      }

      for (const passing of lapPassings) {
        const checkpointIndex = asFiniteNumber(passing.checkpoint_index, null);
        const crossedAtMs = toMillis(passing.timestamp);
        if (
          checkpointIndex === null ||
          checkpointIndex < 0 ||
          !Number.isFinite(crossedAtMs)
        ) {
          continue;
        }
        const sectorTime = asFiniteNumber(passing.sector_time, null);
        const splitTime = asFiniteNumber(passing.split_time, null);
        const trapSpeed = asFiniteNumber(
          passing.trap_speed ?? passing.speed_mps,
          0,
        );
        const lat = asFiniteNumber(passing.lat, 0) || 0;
        const lng = asFiniteNumber(passing.lng, 0) || 0;
        const crossingDocId = `bf_${lapNumber}_${Math.trunc(checkpointIndex)}_${crossedAtMs}`;
        const crossingPayload = {
          lap_number: lapNumber,
          checkpoint_index: Math.trunc(checkpointIndex),
          crossed_at_ms: crossedAtMs,
          speed_mps: trapSpeed || 0,
          lat,
          lng,
          sector_time_ms: sectorTime,
          split_time_ms: splitTime,
          method: 'backfill_passings',
          distance_to_checkpoint_m: 0,
          confidence: 0.5,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        };

        writeOps.push({
          ref: raceSessionCrossingsRef.doc(crossingDocId),
          data: crossingPayload,
          options: { merge: true },
        });
        if (eventSessionCrossingsRef) {
          writeOps.push({
            ref: eventSessionCrossingsRef.doc(crossingDocId),
            data: crossingPayload,
            options: { merge: true },
          });
        }
        result.crossingsRebuilt += 1;
      }
    }

    if (!rebuiltLaps.length) {
      continue;
    }

    const summaryPayload = {
      ...buildSessionSummaryFromLaps(rebuiltLaps),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      backfilled_from_passings: true,
    };
    writeOps.push({ ref: raceSessionSummaryRef, data: summaryPayload });
    if (eventSummaryRef) {
      writeOps.push({ ref: eventSummaryRef, data: summaryPayload });
    }
    writeOps.push({
      ref: raceSessionRef,
      data: {
        backfilled_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      options: { merge: true },
    });
    if (eventSessionParticipantRef) {
      writeOps.push({
        ref: eventSessionParticipantRef,
        data: {
          backfilled_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        options: { merge: true },
      });
    }

    await commitSetOperations(db, writeOps);
    result.participantsUpdated += 1;
  }

  console.log(
    `Backfill completed for race=${raceId} session=${sessionId}: ` +
      `participantsUpdated=${result.participantsUpdated}, ` +
      `laps=${result.lapsRebuilt}, crossings=${result.crossingsRebuilt}`,
  );

  return result;
});
