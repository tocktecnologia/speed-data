const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { PubSub } = require('@google-cloud/pubsub');
const { BigQuery } = require('@google-cloud/bigquery');
const {
  DEFAULT_DEDUP_WINDOW_MS,
  DEFAULT_MIN_LAP_TIME_SECONDS,
  DEFAULT_TRAP_WIDTH_M,
  buildCheckpointLines,
  interpolateLineCrossing,
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
const TRAP_WIDTH_M = DEFAULT_TRAP_WIDTH_M;
const STATE_STALE_RESET_MS = 6 * 60 * 60 * 1000;
const START_FINISH_REARM_DISTANCE_M = 60;
const START_FINISH_REARM_MIN_MS = 1500;
// Strict mode: lap close/open in cloud must come from app local closures only.
const STRICT_LOCAL_LAP_CLOSURE_MODE = true;

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

function sanitizeCheckpointMetricMap(rawMap, { roundValue = false } = {}) {
  const normalized = {};
  if (!rawMap || typeof rawMap !== 'object') return normalized;

  const assignMetric = (rawIndex, rawValue) => {
    const checkpointIndex = asFiniteNumber(rawIndex, null);
    const metric = asFiniteNumber(rawValue, null);
    if (
      checkpointIndex === null ||
      checkpointIndex < 0 ||
      metric === null ||
      metric < 0
    ) {
      return;
    }
    const checkpointKey = Math.trunc(checkpointIndex);
    const normalizedValue = roundValue ? Math.trunc(metric) : metric;
    normalized[checkpointKey] = normalizedValue;
  };

  if (Array.isArray(rawMap)) {
    for (const entry of rawMap) {
      if (!entry || typeof entry !== 'object') continue;
      assignMetric(
        entry.checkpoint_index ?? entry.checkpointIndex ?? entry.index,
        entry.value ?? entry.metric ?? entry.time ?? entry.speed,
      );
    }
    return normalized;
  }

  for (const [rawKey, rawValue] of Object.entries(rawMap)) {
    assignMetric(rawKey, rawValue);
  }

  return normalized;
}

function sanitizeLocalLapClosures(rawClosures) {
  if (!Array.isArray(rawClosures)) return [];

  return rawClosures
    .map((entry, idx) => {
      if (!entry || typeof entry !== 'object') return null;

      const lapNumber = asFiniteNumber(entry.lap_number, null);
      const sfCrossedAtMs = asFiniteNumber(entry.sf_crossed_at_ms, null);
      const postSfPointRaw =
        entry.post_sf_point && typeof entry.post_sf_point === 'object'
          ? entry.post_sf_point
          : null;

      if (!postSfPointRaw) return null;

      const postSfTimestampMs = asFiniteNumber(postSfPointRaw.timestamp, null);
      const postSfLat = asFiniteNumber(postSfPointRaw.lat, null);
      const postSfLng = asFiniteNumber(postSfPointRaw.lng, null);
      if (
        lapNumber === null ||
        sfCrossedAtMs === null ||
        postSfTimestampMs === null ||
        postSfLat === null ||
        postSfLng === null
      ) {
        return null;
      }

      const sfCrossingRaw =
        entry.sf_crossing && typeof entry.sf_crossing === 'object'
          ? entry.sf_crossing
          : {};
      const checkpointTimes = sanitizeCheckpointMetricMap(
        entry.checkpoint_times,
        { roundValue: true },
      );
      const checkpointSpeeds = sanitizeCheckpointMetricMap(entry.checkpoint_speeds);
      const closureIdRaw = entry.closure_id;
      const closureId =
        typeof closureIdRaw === 'string' && closureIdRaw.trim()
          ? closureIdRaw.trim()
          : `auto_${Math.trunc(lapNumber)}_${Math.trunc(sfCrossedAtMs)}_${Math.trunc(postSfTimestampMs)}_${idx}`;

      return {
        closure_id: closureId,
        lap_number: Math.max(1, Math.trunc(lapNumber)),
        next_lap_number: Math.max(
          1,
          Math.trunc(asFiniteNumber(entry.next_lap_number, lapNumber + 1)),
        ),
        lap_time_ms: asFiniteNumber(entry.lap_time_ms, null),
        lap_valid: entry.lap_valid !== false,
        lap_start_ms: asFiniteNumber(entry.lap_start_ms, null),
        lap_end_ms: asFiniteNumber(entry.lap_end_ms, sfCrossedAtMs),
        sf_crossed_at_ms: Math.trunc(sfCrossedAtMs),
        sf_checkpoint_index: Math.trunc(
          asFiniteNumber(entry.sf_checkpoint_index, -1),
        ),
        local_timing_min_lap_ms: asFiniteNumber(entry.local_timing_min_lap_ms, null),
        captured_at_ms: asFiniteNumber(entry.captured_at_ms, postSfTimestampMs),
        checkpoint_times: checkpointTimes,
        checkpoint_speeds: checkpointSpeeds,
        sf_crossing: {
          lat: asFiniteNumber(sfCrossingRaw.lat, null),
          lng: asFiniteNumber(sfCrossingRaw.lng, null),
          speed: asFiniteNumber(sfCrossingRaw.speed, null),
          heading: asFiniteNumber(sfCrossingRaw.heading, null),
          altitude: asFiniteNumber(sfCrossingRaw.altitude, null),
          timestamp: asFiniteNumber(sfCrossingRaw.timestamp, null),
          method:
            typeof sfCrossingRaw.method === 'string'
              ? sfCrossingRaw.method
              : 'local_sf_crossing',
          distance_to_checkpoint_m: asFiniteNumber(
            sfCrossingRaw.distance_to_checkpoint_m,
            null,
          ),
          confidence: asFiniteNumber(sfCrossingRaw.confidence, null),
        },
        post_sf_point: {
          lat: postSfLat,
          lng: postSfLng,
          speed: asFiniteNumber(postSfPointRaw.speed, null),
          heading: asFiniteNumber(postSfPointRaw.heading, null),
          altitude: asFiniteNumber(postSfPointRaw.altitude, null),
          timestamp: Math.trunc(postSfTimestampMs),
          source:
            typeof postSfPointRaw.source === 'string'
              ? postSfPointRaw.source
              : 'gps',
        },
      };
    })
    .filter(Boolean);
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

async function assertAdminAccess(db, auth) {
  if (!auth || !auth.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }

  const tokenRole = (auth.token.role || '').toString().trim().toLowerCase();
  const tokenAdmin =
    auth.token.admin === true || tokenRole === 'admin' || tokenRole === 'root';
  if (tokenAdmin) return;

  const userDoc = await db.collection('users').doc(auth.uid).get();
  const userData = userDoc.exists ? userDoc.data() || {} : {};
  const docRole = (userData.role || '').toString().trim().toLowerCase();
  const docAdmin = docRole === 'admin' || docRole === 'root';
  if (!docAdmin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only administrators can clear session data.',
    );
  }
}

function normalizeRole(value) {
  const role = (value || '').toString().trim().toLowerCase();
  if (role === 'teammember') return 'team_member';
  if (role === 'integrante' || role === 'integrante_equipe') return 'team_member';
  return role;
}

function isAdminRole(value) {
  const role = normalizeRole(value);
  return role === 'admin' || role === 'root';
}

async function isAdminUser(db, auth) {
  if (!auth || !auth.uid) return false;
  const tokenRole = normalizeRole(auth.token.role);
  if (auth.token.admin === true || isAdminRole(tokenRole)) {
    return true;
  }

  const userDoc = await db.collection('users').doc(auth.uid).get();
  const userData = userDoc.exists ? userDoc.data() || {} : {};
  return isAdminRole(userData.role);
}

async function getUserTeamMemberships(db, eventId, uid, userEmail = null) {
  const memberships = [];
  if (!eventId || (!uid && !userEmail)) return memberships;
  const normalizedEmail = (userEmail || '').toString().trim().toLowerCase();

  const teamsSnap = await db.collection('events').doc(eventId).collection('teams').get();
  if (teamsSnap.empty) return memberships;

  const checks = teamsSnap.docs.map(async (teamDoc) => {
    let data = null;
    if (uid) {
      const memberDocByUid = await teamDoc.ref.collection('members').doc(uid).get();
      if (memberDocByUid.exists) {
        data = memberDocByUid.data() || {};
      }
    }

    if (!data && normalizedEmail) {
      const byEmailSnap = await teamDoc.ref
        .collection('members')
        .where('email', '==', normalizedEmail)
        .limit(1)
        .get();
      if (!byEmailSnap.empty) {
        data = byEmailSnap.docs[0].data() || {};
      }
    }

    if (!data) return null;
    if (data.active === false) return null;

    const role = normalizeRole(data.role || 'staff');
    if (role === 'pilot') return null;

    const teamData = teamDoc.data() || {};
    const teamName = (teamData.name || '').toString().trim();
    return {
      teamId: teamDoc.id,
      teamName,
      role,
    };
  });

  const resolved = await Promise.all(checks);
  for (const item of resolved) {
    if (item) memberships.push(item);
  }
  return memberships;
}

async function resolveCompetitorByPilotUid(db, eventId, pilotUid) {
  if (!eventId || !pilotUid) return null;
  const competitorsRef = db.collection('events').doc(eventId).collection('competitors');

  const byUid = await competitorsRef.where('uid', '==', pilotUid).limit(1).get();
  if (!byUid.empty) {
    const doc = byUid.docs[0];
    return { id: doc.id, ...doc.data() };
  }

  const byUserId = await competitorsRef.where('user_id', '==', pilotUid).limit(1).get();
  if (!byUserId.empty) {
    const doc = byUserId.docs[0];
    return { id: doc.id, ...doc.data() };
  }
  return null;
}

async function canUserControlPilotAlert({
  db,
  auth,
  eventId,
  pilotUid,
  requestedTeamId = null,
}) {
  if (!auth || !auth.uid) {
    return { allowed: false, reason: 'unauthenticated' };
  }

  if (await isAdminUser(db, auth)) {
    return { allowed: true, reason: 'admin', teamId: requestedTeamId || null };
  }

  const memberships = await getUserTeamMemberships(
    db,
    eventId,
    auth.uid,
    auth.token && auth.token.email ? auth.token.email : null,
  );
  if (!memberships.length) {
    return { allowed: false, reason: 'no-team-membership' };
  }

  const competitor = await resolveCompetitorByPilotUid(db, eventId, pilotUid);
  if (!competitor) {
    return { allowed: false, reason: 'pilot-not-found' };
  }

  const competitorTeamId = (competitor.team_id || '').toString().trim();
  if (!competitorTeamId) {
    return { allowed: false, reason: 'pilot-without-team' };
  }

  const membershipTeam = memberships.find((item) => item.teamId === competitorTeamId);
  if (!membershipTeam) {
    return { allowed: false, reason: 'pilot-outside-team' };
  }

  if (requestedTeamId && requestedTeamId !== competitorTeamId) {
    return { allowed: false, reason: 'team-mismatch' };
  }

  return {
    allowed: true,
    reason: 'team-member',
    teamId: competitorTeamId,
    teamName: membershipTeam.teamName,
    competitor,
  };
}

function parseSessionType(value) {
  const normalized = (value || '').toString().trim().toLowerCase();
  if (normalized === 'race' || normalized === 'corrida') return 'race';
  if (normalized === 'qualifying' || normalized === 'qualification') return 'qualifying';
  return 'practice';
}

function buildLapPayloadFromLocalClosure(
  closure,
  {
    minLapMs = DEFAULT_MIN_LAP_TIME_SECONDS * 1000,
    minLapTimeSeconds = DEFAULT_MIN_LAP_TIME_SECONDS,
  } = {},
) {
  if (!closure || typeof closure !== 'object') return null;

  const lapNumber = asFiniteNumber(closure.lap_number, null);
  const lapEndMs = asFiniteNumber(
    closure.lap_end_ms,
    asFiniteNumber(closure.sf_crossed_at_ms, null),
  );
  let lapStartMs = asFiniteNumber(closure.lap_start_ms, null);
  let lapTimeMs = asFiniteNumber(closure.lap_time_ms, null);

  if (!Number.isFinite(lapEndMs) || !Number.isFinite(lapNumber)) {
    return null;
  }

  if (!Number.isFinite(lapStartMs) && Number.isFinite(lapTimeMs) && lapTimeMs > 0) {
    lapStartMs = lapEndMs - lapTimeMs;
  }
  if (!Number.isFinite(lapTimeMs) && Number.isFinite(lapStartMs) && lapEndMs > lapStartMs) {
    lapTimeMs = lapEndMs - lapStartMs;
  }
  if (!Number.isFinite(lapStartMs) || !Number.isFinite(lapTimeMs) || lapTimeMs <= 0) {
    return null;
  }

  const closureMinLapMs = asFiniteNumber(closure.local_timing_min_lap_ms, null);
  const effectiveMinLapMs =
    Number.isFinite(closureMinLapMs) && closureMinLapMs > 0 ? closureMinLapMs : minLapMs;
  const effectiveMinLapSeconds = Math.max(
    1,
    Math.trunc(effectiveMinLapMs / 1000) || minLapTimeSeconds,
  );
  const closureValid = closure.lap_valid !== false;
  const valid = closureValid && lapTimeMs >= effectiveMinLapMs;
  const invalidReasons = [];
  if (lapTimeMs < effectiveMinLapMs) {
    invalidReasons.push(`min_lap_time_seconds_${effectiveMinLapSeconds}`);
  }
  if (!closureValid) {
    invalidReasons.push('local_closure_invalid');
  }

  const sfSpeed = asFiniteNumber(
    closure.sf_crossing && typeof closure.sf_crossing === 'object'
      ? closure.sf_crossing.speed
      : null,
    null,
  );
  const sfCheckpointIndex = Math.trunc(
    asFiniteNumber(closure.sf_checkpoint_index, -1),
  );
  const checkpointTimesRaw = sanitizeCheckpointMetricMap(
    closure.checkpoint_times,
    { roundValue: true },
  );
  const checkpointSpeedsRaw = sanitizeCheckpointMetricMap(closure.checkpoint_speeds);
  const hasClosureCheckpointTimes = Object.keys(checkpointTimesRaw).length > 0;
  const checkpointTimes = {};
  for (const [rawIndex, rawTs] of Object.entries(checkpointTimesRaw)) {
    const checkpointIndex = asFiniteNumber(rawIndex, null);
    const checkpointTs = asFiniteNumber(rawTs, null);
    if (checkpointIndex === null || checkpointTs === null) continue;
    if (checkpointTs < lapStartMs || checkpointTs > lapEndMs) continue;
    checkpointTimes[Math.trunc(checkpointIndex)] = Math.trunc(checkpointTs);
  }
  if (hasClosureCheckpointTimes) {
    checkpointTimes[0] = Math.trunc(
      asFiniteNumber(checkpointTimes[0], Math.trunc(lapStartMs)),
    );
    if (sfCheckpointIndex >= 0) {
      checkpointTimes[sfCheckpointIndex] = Math.trunc(lapEndMs);
    }
  }

  const checkpointSpeeds = {};
  for (const [rawIndex, rawSpeed] of Object.entries(checkpointSpeedsRaw)) {
    const checkpointIndex = asFiniteNumber(rawIndex, null);
    const checkpointSpeed = asFiniteNumber(rawSpeed, null);
    if (
      checkpointIndex === null ||
      checkpointIndex < 0 ||
      checkpointSpeed === null ||
      checkpointSpeed <= 0
    ) {
      continue;
    }
    checkpointSpeeds[Math.trunc(checkpointIndex)] = checkpointSpeed;
  }
  if (
    Number.isFinite(sfSpeed) &&
    sfCheckpointIndex >= 0 &&
    !Number.isFinite(asFiniteNumber(checkpointSpeeds[sfCheckpointIndex], null))
  ) {
    checkpointSpeeds[sfCheckpointIndex] = sfSpeed;
  }

  const lapFromClosureCheckpoints = hasClosureCheckpointTimes
    ? buildLapPayloadFromState({
      lapNumber: Math.max(1, Math.trunc(lapNumber)),
      lapStartMs: Math.trunc(lapStartMs),
      lapEndMs: Math.trunc(lapEndMs),
      checkpointTimes,
      checkpointSpeeds,
      minLapMs: effectiveMinLapMs,
      minLapTimeSeconds: effectiveMinLapSeconds,
    })
    : null;

  let splitsMs = [];
  let sectorsMs = [];
  let trapSpeedsMps = [];
  let speedStats = null;
  if (lapFromClosureCheckpoints) {
    splitsMs = Array.isArray(lapFromClosureCheckpoints.splits_ms)
      ? lapFromClosureCheckpoints.splits_ms
      : [];
    sectorsMs = Array.isArray(lapFromClosureCheckpoints.sectors_ms)
      ? lapFromClosureCheckpoints.sectors_ms
      : [];
    trapSpeedsMps = Array.isArray(lapFromClosureCheckpoints.trap_speeds_mps)
      ? lapFromClosureCheckpoints.trap_speeds_mps
      : [];
    speedStats =
      lapFromClosureCheckpoints.speed_stats &&
      typeof lapFromClosureCheckpoints.speed_stats === 'object'
        ? lapFromClosureCheckpoints.speed_stats
        : null;
  }
  if (!trapSpeedsMps.length && Number.isFinite(sfSpeed)) {
    trapSpeedsMps = [sfSpeed];
  }
  if (!speedStats && trapSpeedsMps.length) {
    speedStats = {
      min_mps: Math.min(...trapSpeedsMps),
      max_mps: Math.max(...trapSpeedsMps),
      avg_mps: trapSpeedsMps.reduce((sum, value) => sum + value, 0) / trapSpeedsMps.length,
    };
  }

  return {
    number: Math.max(1, Math.trunc(lapNumber)),
    lap_start_ms: Math.trunc(lapStartMs),
    lap_end_ms: Math.trunc(lapEndMs),
    total_lap_time_ms: Math.trunc(lapTimeMs),
    splits_ms: splitsMs,
    sectors_ms: sectorsMs,
    trap_speeds_mps: trapSpeedsMps,
    speed_stats: speedStats,
    valid,
    invalid_reasons: [...new Set(invalidReasons)],
    source: 'local_closure',
    closure_id:
      typeof closure.closure_id === 'string' && closure.closure_id.trim()
        ? closure.closure_id.trim()
        : null,
    captured_at_ms: asFiniteNumber(closure.captured_at_ms, null),
  };
}

async function rebuildSessionSummaryFromLapDocs(summaryRefs, preferredLapsRef) {
  if (!preferredLapsRef || !summaryRefs.length) return;
  const lapsSnap = await preferredLapsRef.get();
  const rebuiltLaps = lapsSnap.docs
    .map((doc) => {
      const data = doc.data() || {};
      const lapNumberFromDocId =
        typeof doc.id === 'string' && doc.id.startsWith('lap_')
          ? asFiniteNumber(doc.id.replace('lap_', ''), null)
          : null;
      return {
        ...data,
        number: Math.trunc(
          asFiniteNumber(data.number, lapNumberFromDocId !== null ? lapNumberFromDocId : 0),
        ),
        total_lap_time_ms: asFiniteNumber(data.total_lap_time_ms, null),
        valid: data.valid === true,
      };
    })
    .filter(
      (lap) =>
        Number.isFinite(lap.number) &&
        Number.isFinite(lap.total_lap_time_ms) &&
        lap.total_lap_time_ms > 0,
    );

  const summaryPayload = {
    ...buildSessionSummaryFromLaps(rebuiltLaps),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    source: 'hybrid_local_priority',
  };

  const summaryWrites = summaryRefs.map((ref) => ({
    ref,
    data: summaryPayload,
    options: { merge: true },
  }));
  await commitSetOperations(admin.firestore(), summaryWrites);
}

async function materializeParticipantSessionFromPassings({
  db,
  raceId,
  eventId,
  sessionId,
  uid,
  minLapMs,
  minLapTimeSeconds,
}) {
  const result = {
    updated: false,
    lapsRebuilt: 0,
    crossingsRebuilt: 0,
  };
  if (!db || !raceId || !sessionId || !uid) {
    return result;
  }

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
    return result;
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
    return result;
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
      materialized_from_passings: true,
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
      const sectorTime = asFiniteNumber(
        passing.sector_time ?? passing.sector_time_ms,
        null,
      );
      const splitTime = asFiniteNumber(
        passing.split_time ?? passing.split_time_ms,
        null,
      );
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
    return result;
  }

  const summaryPayload = {
    ...buildSessionSummaryFromLaps(rebuiltLaps),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    materialized_from_passings: true,
    backfilled_from_passings: true,
  };
  writeOps.push({
    ref: raceSessionSummaryRef,
    data: summaryPayload,
    options: { merge: true },
  });
  if (eventSummaryRef) {
    writeOps.push({
      ref: eventSummaryRef,
      data: summaryPayload,
      options: { merge: true },
    });
  }
  writeOps.push({
    ref: raceSessionRef,
    data: {
      backfilled_at: admin.firestore.FieldValue.serverTimestamp(),
      materialized_from_passings_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    options: { merge: true },
  });
  if (eventSessionParticipantRef) {
    writeOps.push({
      ref: eventSessionParticipantRef,
      data: {
        backfilled_at: admin.firestore.FieldValue.serverTimestamp(),
        materialized_from_passings_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      options: { merge: true },
    });
  }

  await commitSetOperations(db, writeOps);
  result.updated = true;
  return result;
}

exports.ingestTelemetry = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in to send telemetry.');
  }

  const {
    raceId,
    eventId: inputEventId,
    uid,
    points: rawPoints,
    checkpoints,
    timelines,
    sessionId: inputSessionId,
    session,
    minLapTimeSeconds,
    localLapClosures: rawLocalLapClosures,
  } = data;

  if (rawPoints != null && !Array.isArray(rawPoints)) {
    throw new functions.https.HttpsError('invalid-argument', 'Points must be an array.');
  }
  if (rawLocalLapClosures != null && !Array.isArray(rawLocalLapClosures)) {
    throw new functions.https.HttpsError('invalid-argument', 'localLapClosures must be an array.');
  }

  const points = Array.isArray(rawPoints) ? rawPoints : [];
  const localLapClosures = sanitizeLocalLapClosures(rawLocalLapClosures);
  const sessionId = inputSessionId || session || null;
  const eventIdFromPoints =
    points
      .map((point) => {
        if (!point || typeof point !== 'object') return null;
        const raw = point.eventId || point.event_id;
        return typeof raw === 'string' && raw.trim() ? raw.trim() : null;
      })
      .find((value) => value) || null;
  const eventIdFromRawClosures = Array.isArray(rawLocalLapClosures)
    ? rawLocalLapClosures
        .map((closure) => {
          if (!closure || typeof closure !== 'object') return null;
          const raw = closure.event_id || closure.eventId;
          return typeof raw === 'string' && raw.trim() ? raw.trim() : null;
        })
        .find((value) => value) || null
    : null;
  let eventId = inputEventId || eventIdFromPoints || eventIdFromRawClosures || null;
  const minLapMs = (minLapTimeSeconds || DEFAULT_MIN_LAP_TIME_SECONDS) * 1000;

  if (!raceId || !uid) {
    throw new functions.https.HttpsError('invalid-argument', 'raceId and uid are required.');
  }
  if (!points.length && !localLapClosures.length) {
    return { success: true, count: 0, localLapClosures: 0 };
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
      `checkpoints=${effectiveCheckpoints.length}, timelines=${Array.isArray(timelines) ? timelines.length : 0}, ` +
      `localLapClosures=${localLapClosures.length})`,
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
  const eventLocalLapClosuresRef = eventSessionRef ? eventSessionRef.collection('local_lap_closures') : null;
  const legacyLocalLapClosuresRef = db.collection('races').doc(raceId).collection('local_lap_closures');

  const passingsRefs = [legacyPassingsRef, eventPassingsRef].filter(Boolean);
  const crossingsRefs = [legacyCrossingsRef, eventCrossingsRef].filter(Boolean);
  const sessionLapsRefs = [legacySessionLapsRef, eventSessionLapsRef].filter(Boolean);
  const summaryRefs = [legacySummaryRef, eventSummaryRef].filter(Boolean);
  const stateRefs = [legacyStateRef, eventStateRef].filter(Boolean);
  const localLapClosureRefs = [legacyLocalLapClosuresRef, eventLocalLapClosuresRef].filter(Boolean);

  const buildRealtimePayloadFromPoint = (rawPoint) => {
    if (!rawPoint || typeof rawPoint !== 'object') return null;
    const lat = asFiniteNumber(rawPoint.lat, null);
    const lng = asFiniteNumber(rawPoint.lng, null);
    const timestampMs = asFiniteNumber(rawPoint.timestamp, null);
    if (lat === null || lng === null || timestampMs === null) return null;

    return {
      lat,
      lng,
      speed: asFiniteNumber(rawPoint.speed, 0) || 0,
      heading: asFiniteNumber(rawPoint.heading, 0) || 0,
      altitude: asFiniteNumber(rawPoint.altitude, 0) || 0,
      timestamp: Math.trunc(timestampMs),
      ingested_at: Date.now(),
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
    };
  };

  const upsertRealtimeParticipantSnapshot = async (rawPoint) => {
    const realtime = buildRealtimePayloadFromPoint(rawPoint);
    if (!realtime) return;

    const tasks = [
      legacyParticipantRef.set(
        {
          current: realtime,
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      ),
    ];

    if (legacyStateRef) {
      tasks.push(
        legacyStateRef.set(
          {
            current: realtime,
          },
          { merge: true },
        ),
      );
    }

    if (eventSessionParticipantRef) {
      tasks.push(
        eventSessionParticipantRef.set(
          {
            current: realtime,
            last_updated: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        ),
      );
    }

    if (eventStateRef) {
      tasks.push(
        eventStateRef.set(
          {
            current: realtime,
          },
          { merge: true },
        ),
      );
    }

    await Promise.all(tasks);
  };

  if (localLapClosures.length && localLapClosureRefs.length) {
    const writeOps = [];
    for (const closure of localLapClosures) {
      const payload = {
        ...closure,
        participant_uid: uid,
        session_id: sessionId || null,
        event_id: eventId || null,
        race_id: raceId,
        received_at: admin.firestore.FieldValue.serverTimestamp(),
      };
      for (const ref of localLapClosureRefs) {
        writeOps.push({
          ref: ref.doc(closure.closure_id),
          data: payload,
          options: { merge: true },
        });
      }
    }
    await commitSetOperations(db, writeOps);
  }

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
      awaiting_sf_rearm: false,
      last_sf_crossed_at_ms: null,
      checkpoint_times: {},
      checkpoint_speeds: {},
      last_point: null,
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
        awaiting_sf_rearm: false,
        last_sf_crossed_at_ms: null,
        checkpoint_times: {},
        checkpoint_speeds: {},
        last_point: null,
      };
      console.log(`Resetting stale lap state for user ${uid} session ${sessionId || 'legacy'}`);
    }
  }

  state.lap_number = Math.max(1, Math.trunc(asFiniteNumber(state.lap_number, 1) || 1));
  state.last_checkpoint_index = Math.trunc(
    asFiniteNumber(state.last_checkpoint_index, -1) || -1,
  );
  state.lap_start_ms = asFiniteNumber(state.lap_start_ms, null);
  state.last_crossed_at_ms = asFiniteNumber(state.last_crossed_at_ms, null);
  state.awaiting_sf_rearm = state.awaiting_sf_rearm === true;
  state.last_sf_crossed_at_ms = asFiniteNumber(state.last_sf_crossed_at_ms, null);
  state.checkpoint_times =
    state.checkpoint_times && typeof state.checkpoint_times === 'object'
      ? state.checkpoint_times
      : {};
  state.checkpoint_speeds =
    state.checkpoint_speeds && typeof state.checkpoint_speeds === 'object'
      ? state.checkpoint_speeds
      : {};
  let shouldMaterializeSessionFromPassings = localLapClosures.length > 0;

  try {
    const hasLocalClosures = localLapClosures.length > 0;

    if (hasLocalClosures) {
      const preferredLapsRef = eventSessionLapsRef || legacySessionLapsRef || null;
      const fallbackFinishCheckpointIndex =
        Array.isArray(effectiveCheckpoints) && effectiveCheckpoints.length > 1
          ? effectiveCheckpoints.length - 1
          : 0;
      const sortedClosures = [...localLapClosures].sort((a, b) => {
        const aTs = asFiniteNumber(a.sf_crossed_at_ms, 0);
        const bTs = asFiniteNumber(b.sf_crossed_at_ms, 0);
        return aTs - bTs;
      });
      const materializedOps = [];

      for (const closure of sortedClosures) {
        const closureId =
          typeof closure.closure_id === 'string' && closure.closure_id.trim()
            ? closure.closure_id.trim()
            : null;
        if (!closureId) continue;

        const lapPayloadBase = buildLapPayloadFromLocalClosure(closure, {
          minLapMs,
          minLapTimeSeconds,
        });
        if (!lapPayloadBase) continue;

        const lapNumber = lapPayloadBase.number;
        const nextLapNumber = Math.max(
          1,
          Math.trunc(asFiniteNumber(closure.next_lap_number, lapNumber + 1)),
        );
        const lapDocId = `lap_${lapNumber}`;
        const lapPayload = {
          ...lapPayloadBase,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        };

        for (const ref of sessionLapsRefs) {
          materializedOps.push({
            ref: ref.doc(lapDocId),
            data: lapPayload,
            options: { merge: true },
          });
        }
        materializedOps.push({
          ref: legacyLapsRef.doc(lapDocId),
          data: {
            ...lapPayload,
            session_id: sessionId || null,
            event_id: eventId || null,
          },
          options: { merge: true },
        });

        const sfCrossing =
          closure.sf_crossing && typeof closure.sf_crossing === 'object'
            ? closure.sf_crossing
            : {};
        const postSfPoint =
          closure.post_sf_point && typeof closure.post_sf_point === 'object'
            ? closure.post_sf_point
            : {};
        const sfCrossedAtMs = Math.trunc(
          asFiniteNumber(closure.sf_crossed_at_ms, lapPayload.lap_end_ms),
        );
        const sfCheckpointIndexRaw = asFiniteNumber(
          closure.sf_checkpoint_index,
          fallbackFinishCheckpointIndex,
        );
        const sfCheckpointIndex = Number.isFinite(sfCheckpointIndexRaw)
          ? Math.max(0, Math.trunc(sfCheckpointIndexRaw))
          : fallbackFinishCheckpointIndex;

        const closingPassingPayload = {
          participant_uid: uid,
          lap_number: lapNumber,
          lap_time: lapPayload.total_lap_time_ms,
          timestamp: admin.firestore.Timestamp.fromMillis(sfCrossedAtMs),
          session_id: sessionId || null,
          event_id: eventId || null,
          race_id: raceId,
          checkpoint_index: sfCheckpointIndex,
          flags: ['local_closure'],
          sector_time: null,
          split_time: lapPayload.total_lap_time_ms,
          trap_speed: asFiniteNumber(sfCrossing.speed, null),
          valid: lapPayload.valid,
          lat: asFiniteNumber(sfCrossing.lat, asFiniteNumber(postSfPoint.lat, null)),
          lng: asFiniteNumber(sfCrossing.lng, asFiniteNumber(postSfPoint.lng, null)),
          source: 'local_closure',
          closure_id: closureId,
        };
        for (const ref of passingsRefs) {
          materializedOps.push({
            ref: ref.doc(`lc_${closureId}_sf`),
            data: closingPassingPayload,
            options: { merge: true },
          });
        }

        const openingTimestampMs = sfCrossedAtMs;
        const openingSpeed = asFiniteNumber(
          sfCrossing.speed,
          asFiniteNumber(postSfPoint.speed, 0),
        ) || 0;
        const openPassingPayload = {
          participant_uid: uid,
          lap_number: nextLapNumber,
          lap_time: null,
          timestamp: admin.firestore.Timestamp.fromMillis(
            Math.trunc(openingTimestampMs),
          ),
          session_id: sessionId || null,
          event_id: eventId || null,
          race_id: raceId,
          checkpoint_index: 0,
          flags: ['auto_open', 'local_closure'],
          sector_time: null,
          split_time: 0,
          trap_speed: openingSpeed,
          lat: asFiniteNumber(sfCrossing.lat, asFiniteNumber(postSfPoint.lat, null)),
          lng: asFiniteNumber(sfCrossing.lng, asFiniteNumber(postSfPoint.lng, null)),
          source: 'local_closure',
          closure_id: closureId,
        };
        for (const ref of passingsRefs) {
          materializedOps.push({
            ref: ref.doc(`lc_${closureId}_open`),
            data: openPassingPayload,
            options: { merge: true },
          });
        }

        state.lap_number = nextLapNumber;
        state.lap_start_ms = Math.trunc(openingTimestampMs);
        state.last_checkpoint_index = 0;
        state.last_crossed_at_ms = Math.trunc(openingTimestampMs);
        state.checkpoint_times = { 0: Math.trunc(openingTimestampMs) };
        state.checkpoint_speeds = { 0: openingSpeed };
        state.awaiting_sf_rearm = true;
        state.last_sf_crossed_at_ms = sfCrossedAtMs;
      }

      await commitSetOperations(db, materializedOps);
      shouldMaterializeSessionFromPassings = true;

      if (stateRefs.length) {
        const stateOps = stateRefs.map((ref) => ({
          ref,
          data: state,
          options: { merge: true },
        }));
        await commitSetOperations(db, stateOps);
      }

      await rebuildSessionSummaryFromLapDocs(summaryRefs, preferredLapsRef);
    }

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
      const checkpointLines = buildCheckpointLines(
        effectiveCheckpoints,
        TRAP_WIDTH_M,
      );

      const normalizedPoints = points
        .map((raw) => ({
          lat: Number(raw && raw.lat),
          lng: Number(raw && raw.lng),
          speed: Number(raw && raw.speed),
          heading: Number(raw && raw.heading),
          altitude: Number(raw && raw.altitude),
          timestamp: Number(raw && raw.timestamp),
        }))
        .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lng) && Number.isFinite(p.timestamp))
        .sort((a, b) => a.timestamp - b.timestamp);

      state.lap_number = Math.max(1, Math.trunc(asFiniteNumber(state.lap_number, 1) || 1));
      state.last_checkpoint_index = Math.trunc(asFiniteNumber(state.last_checkpoint_index, -1) || -1);
      state.lap_start_ms = asFiniteNumber(state.lap_start_ms, null);
      state.last_crossed_at_ms = asFiniteNumber(state.last_crossed_at_ms, null);
      state.awaiting_sf_rearm = state.awaiting_sf_rearm === true;
      state.last_sf_crossed_at_ms = asFiniteNumber(state.last_sf_crossed_at_ms, null);
      state.checkpoint_times =
        state.checkpoint_times && typeof state.checkpoint_times === 'object'
          ? state.checkpoint_times
          : {};
      state.checkpoint_speeds =
        state.checkpoint_speeds && typeof state.checkpoint_speeds === 'object'
          ? state.checkpoint_speeds
          : {};

      const previousPoint =
        state.last_point &&
        Number.isFinite(Number(state.last_point.lat)) &&
        Number.isFinite(Number(state.last_point.lng)) &&
        Number.isFinite(Number(state.last_point.timestamp))
          ? {
            lat: Number(state.last_point.lat),
            lng: Number(state.last_point.lng),
            speed: Number(state.last_point.speed),
            heading: Number(state.last_point.heading),
            altitude: Number(state.last_point.altitude),
            timestamp: Number(state.last_point.timestamp),
          }
          : null;

      const segmentPoints = [];
      if (
        previousPoint &&
        normalizedPoints.length &&
        previousPoint.timestamp < normalizedPoints[0].timestamp
      ) {
        segmentPoints.push(previousPoint);
      }
      segmentPoints.push(...normalizedPoints);

      const persistState = async () => {
        if (!stateRefs.length) return;
        await Promise.all(stateRefs.map((ref) => ref.set(state, { merge: true })));
      };

      let selectedInterpolatedCrossings = 0;
      let selectedFallbackCrossings = 0;

      for (let idx = 1; idx < segmentPoints.length; idx++) {
        const pointA = segmentPoints[idx - 1];
        const pointB = segmentPoints[idx];
        if (!Number.isFinite(pointA.timestamp) || !Number.isFinite(pointB.timestamp)) {
          continue;
        }
        if (pointB.timestamp <= pointA.timestamp) {
          continue;
        }

        if (state.awaiting_sf_rearm) {
          const finishCheckpoint = effectiveCheckpoints[finishCheckpointIndex];
          if (
            finishCheckpoint &&
            Number.isFinite(pointB.lat) &&
            Number.isFinite(pointB.lng)
          ) {
            const distanceToFinishM = getDistanceMeters(
              finishCheckpoint.lat,
              finishCheckpoint.lng,
              pointB.lat,
              pointB.lng,
            );
            const timeSinceFinishMs = Number.isFinite(state.last_sf_crossed_at_ms)
              ? pointB.timestamp - state.last_sf_crossed_at_ms
              : START_FINISH_REARM_MIN_MS;
            if (
              distanceToFinishM >= START_FINISH_REARM_DISTANCE_M &&
              timeSinceFinishMs >= START_FINISH_REARM_MIN_MS
            ) {
              state.awaiting_sf_rearm = false;
              state.last_sf_crossed_at_ms = null;
            }
          }
        }

        const crossingCandidates = [];
        for (const line of checkpointLines) {
          if (!line) continue;
          const rawCheckpointIndex = line.index;
          if (rawCheckpointIndex < 0 || rawCheckpointIndex > finishCheckpointIndex) {
            continue;
          }

          // Avoid ambiguity when start and finish share the same physical line.
          if (startFinishSamePoint) {
            if (!state.lap_start_ms && rawCheckpointIndex === finishCheckpointIndex) {
              continue;
            }
            if (state.lap_start_ms && rawCheckpointIndex === 0) {
              continue;
            }
          }
          if (rawCheckpointIndex === finishCheckpointIndex && state.awaiting_sf_rearm) {
            continue;
          }

          if (STRICT_LOCAL_LAP_CLOSURE_MODE && rawCheckpointIndex === finishCheckpointIndex) {
            // Strict mode: never close/open laps from raw points in cloud.
            continue;
          }

          let crossingCandidate = interpolateLineCrossing(line, pointA, pointB);

          // Fallback path (legacy-like): if exact line crossing isn't found in
          // the segment, allow nearest-point capture near checkpoint.
          if (!crossingCandidate) {
            const checkpoint = effectiveCheckpoints[rawCheckpointIndex];
            if (checkpoint) {
              const distToCheckpoint = getDistanceMeters(
                checkpoint.lat,
                checkpoint.lng,
                pointB.lat,
                pointB.lng,
              );
              if (distToCheckpoint <= CHECKPOINT_DISTANCE_TOLERANCE_M) {
                let passesDirectionGate = true;
                if (rawCheckpointIndex !== finishCheckpointIndex) {
                  const nextCheckpoint =
                    rawCheckpointIndex < finishCheckpointIndex
                      ? effectiveCheckpoints[rawCheckpointIndex + 1]
                      : null;
                  if (nextCheckpoint) {
                    const vTrackLat = nextCheckpoint.lat - checkpoint.lat;
                    const vTrackLng = nextCheckpoint.lng - checkpoint.lng;
                    const vPilotLat = pointB.lat - checkpoint.lat;
                    const vPilotLng = pointB.lng - checkpoint.lng;
                    const dot = vPilotLat * vTrackLat + vPilotLng * vTrackLng;
                    const lenSq = vTrackLat * vTrackLat + vTrackLng * vTrackLng;
                    if (dot < 0 || dot > lenSq) {
                      passesDirectionGate = false;
                    }
                  }
                }

                if (passesDirectionGate) {
                  crossingCandidate = {
                    checkpointIndex: rawCheckpointIndex,
                    timestamp: Math.trunc(pointB.timestamp),
                    lat: pointB.lat,
                    lng: pointB.lng,
                    speed: Number.isFinite(pointB.speed) ? pointB.speed : 0,
                    heading: Number.isFinite(pointB.heading) ? pointB.heading : 0,
                    altitude: Number.isFinite(pointB.altitude) ? pointB.altitude : 0,
                    alpha: null,
                    line_offset_m: 0,
                    distance_to_checkpoint_m: distToCheckpoint,
                    method: 'nearest_point_fallback',
                    confidence: 0.7,
                  };
                }
              }
            }
          }

          if (!crossingCandidate) continue;

          const openingOnSharedLine =
            startFinishSamePoint &&
            rawCheckpointIndex === finishCheckpointIndex &&
            !state.lap_start_ms;
          const checkpointIndex = openingOnSharedLine ? 0 : rawCheckpointIndex;

          const shouldSkip = shouldSkipCheckpointCrossing({
            lastCheckpointIndex: state.last_checkpoint_index,
            checkpointIndex,
            lastCrossedAtMs: state.last_crossed_at_ms,
            crossedAtMs: crossingCandidate.timestamp,
            finishCheckpointIndex,
            dedupWindowMs: DEDUP_WINDOW_MS,
          });
          if (shouldSkip) {
            continue;
          }

          const ignoreFinishAtLapOpen =
            startFinishSamePoint &&
            rawCheckpointIndex === finishCheckpointIndex &&
            state.lap_start_ms &&
            crossingCandidate.timestamp - state.lap_start_ms < minLapMs;
          if (ignoreFinishAtLapOpen) {
            continue;
          }

          crossingCandidates.push({
            crossing: crossingCandidate,
            rawCheckpointIndex,
            checkpointIndex,
            openingOnSharedLine,
          });
        }

        if (!crossingCandidates.length) {
          continue;
        }

        crossingCandidates.sort((a, b) => {
          if (a.crossing.timestamp !== b.crossing.timestamp) {
            return a.crossing.timestamp - b.crossing.timestamp;
          }
          return Math.abs(a.crossing.line_offset_m || 0) - Math.abs(b.crossing.line_offset_m || 0);
        });

        const selected = crossingCandidates[0];
        const crossing = selected.crossing;
        const checkpointIndex = selected.checkpointIndex;
        const rawCheckpointIndex = selected.rawCheckpointIndex;
        const openingOnSharedLine = selected.openingOnSharedLine;
        if (crossing.method === 'line_interpolation') {
          selectedInterpolatedCrossings += 1;
        } else {
          selectedFallbackCrossings += 1;
        }
        const lapNumber = state.lap_number || 1;
        const prevTs = state.checkpoint_times ? state.checkpoint_times[checkpointIndex - 1] : null;
        const lapStartTs = state.lap_start_ms;
        const sectorTime = prevTs ? crossing.timestamp - prevTs : null;
        const splitTime = lapStartTs ? crossing.timestamp - lapStartTs : null;

        if (crossingsRefs.length) {
          const crossingPayload = {
            lap_number: lapNumber,
            checkpoint_index: checkpointIndex,
            crossed_at_ms: crossing.timestamp,
            speed_mps: crossing.speed,
            lat: crossing.lat,
            lng: crossing.lng,
            sector_time_ms: sectorTime,
            split_time_ms: splitTime,
            method: crossing.method,
            distance_to_checkpoint_m: crossing.distance_to_checkpoint_m || 0,
            line_offset_m: crossing.line_offset_m,
            confidence: crossing.confidence,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          };
          await Promise.all(crossingsRefs.map((ref) => ref.add(crossingPayload)));
        }

        const passingPayload = {
          participant_uid: uid,
          lap_number: lapNumber,
          lap_time: null,
          timestamp: admin.firestore.Timestamp.fromMillis(crossing.timestamp),
          session_id: sessionId || null,
          event_id: eventId || null,
          race_id: raceId,
          checkpoint_index: checkpointIndex,
          flags: [],
          sector_time: sectorTime,
          split_time: splitTime,
          trap_speed: crossing.speed,
          lat: crossing.lat,
          lng: crossing.lng,
        };
        await Promise.all(passingsRefs.map((ref) => ref.add(passingPayload)));
        shouldMaterializeSessionFromPassings = true;

        state.last_checkpoint_index = checkpointIndex;
        state.last_crossed_at_ms = crossing.timestamp;
        state.checkpoint_times = state.checkpoint_times || {};
        state.checkpoint_speeds = state.checkpoint_speeds || {};
        state.checkpoint_times[checkpointIndex] = crossing.timestamp;
        state.checkpoint_speeds[checkpointIndex] = crossing.speed;
        if (rawCheckpointIndex === finishCheckpointIndex) {
          state.awaiting_sf_rearm = true;
          state.last_sf_crossed_at_ms = crossing.timestamp;
        }

        if (checkpointIndex === 0 && !state.lap_start_ms) {
          state.lap_start_ms = crossing.timestamp;
        }

        if (rawCheckpointIndex === finishCheckpointIndex && state.lap_start_ms && !openingOnSharedLine) {
          const lapStart = state.lap_start_ms;
          const lapEnd = crossing.timestamp;
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
            trap_speed: crossing.speed,
            valid,
            lat: crossing.lat,
            lng: crossing.lng,
          };
          await Promise.all(passingsRefs.map((ref) => ref.add(closingPassingPayload)));
          shouldMaterializeSessionFromPassings = true;

          const nextLapNumber = lapNumber + 1;
          if (startFinishSamePoint) {
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
              trap_speed: crossing.speed,
              lat: crossing.lat,
              lng: crossing.lng,
            };
            await Promise.all(passingsRefs.map((ref) => ref.add(autoOpenPayload)));
            shouldMaterializeSessionFromPassings = true;

            state.lap_number = nextLapNumber;
            state.lap_start_ms = lapEnd;
            state.last_checkpoint_index = 0;
            state.last_crossed_at_ms = lapEnd;
            state.checkpoint_times = { 0: lapEnd };
            state.checkpoint_speeds = { 0: crossing.speed };
          } else {
            state.lap_number = nextLapNumber;
            state.lap_start_ms = null;
            state.last_checkpoint_index = finishCheckpointIndex;
            state.last_crossed_at_ms = lapEnd;
            state.checkpoint_times = {};
            state.checkpoint_speeds = {};
          }
        } else if (rawCheckpointIndex === 0 && !state.lap_start_ms) {
          state.lap_start_ms = crossing.timestamp;
        }

        await persistState();
      }

      if (normalizedPoints.length) {
        const last = normalizedPoints[normalizedPoints.length - 1];
        state.last_point = {
          lat: last.lat,
          lng: last.lng,
          speed: last.speed,
          heading: last.heading,
          altitude: last.altitude,
          timestamp: last.timestamp,
        };
        await persistState();
      }

      if (segmentPoints.length > 1) {
        console.log(
          `Crossing summary user=${uid} session=${sessionId || 'legacy'} ` +
            `segments=${segmentPoints.length - 1} ` +
            `interpolated=${selectedInterpolatedCrossings} ` +
            `fallback=${selectedFallbackCrossings}`,
        );
      }
    }
  } catch (e) {
    console.error('Error in ingestTelemetry algorithm:', e);
  }

  let realtimePointForSnapshot = null;
  if (points.length) {
    realtimePointForSnapshot = points[points.length - 1];
  } else if (localLapClosures.length) {
    const latestClosurePoint = [...localLapClosures]
      .map((closure) => {
        const postSfPoint =
          closure && closure.post_sf_point && typeof closure.post_sf_point === 'object'
            ? closure.post_sf_point
            : null;
        if (!postSfPoint) return null;
        return {
          lat: asFiniteNumber(postSfPoint.lat, null),
          lng: asFiniteNumber(postSfPoint.lng, null),
          speed: asFiniteNumber(postSfPoint.speed, null),
          heading: asFiniteNumber(postSfPoint.heading, null),
          altitude: asFiniteNumber(postSfPoint.altitude, null),
          timestamp: asFiniteNumber(
            postSfPoint.timestamp,
            asFiniteNumber(closure.sf_crossed_at_ms, null),
          ),
        };
      })
      .filter((point) => point && Number.isFinite(point.timestamp))
      .sort((a, b) => a.timestamp - b.timestamp)
      .pop();

    realtimePointForSnapshot = latestClosurePoint || null;
  }

  if (realtimePointForSnapshot) {
    try {
      await upsertRealtimeParticipantSnapshot(realtimePointForSnapshot);
    } catch (realtimeError) {
      console.warn('Failed to upsert realtime participant snapshot:', realtimeError);
    }
  }

  if (sessionId && shouldMaterializeSessionFromPassings) {
    try {
      const materializeResult = await materializeParticipantSessionFromPassings({
        db,
        raceId,
        eventId,
        sessionId,
        uid,
        minLapMs,
        minLapTimeSeconds,
      });
      if (materializeResult.updated) {
        console.log(
          `Materialized from passings user=${uid} session=${sessionId}: ` +
            `laps=${materializeResult.lapsRebuilt}, ` +
            `crossings=${materializeResult.crossingsRebuilt}`,
        );
      }
    } catch (materializeError) {
      console.warn(
        `Failed to materialize passings for user=${uid} session=${sessionId}:`,
        materializeError,
      );
    }
  }

  if (!points.length) {
    return {
      success: true,
      count: 0,
      localLapClosures: localLapClosures.length,
    };
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
    localLapClosuresCount: localLapClosures.length,
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

exports.sendPilotAlert = functions.https.onCall(async (data, context) => {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }

  const eventId = (data.eventId || '').toString().trim();
  const sessionId = (data.sessionId || '').toString().trim();
  const pilotUid = (data.pilotUid || '').toString().trim();
  const requestedTeamId = (data.teamId || '').toString().trim() || null;
  const type = (data.type || 'custom').toString().trim().toLowerCase();
  const rawMessage = (data.message || '').toString().replace(/\s+/g, ' ').trim();
  const message = type === 'box' ? 'BOX' : rawMessage;

  if (!eventId || !sessionId || !pilotUid) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'eventId, sessionId and pilotUid are required.',
    );
  }
  if (!message || message.length > 32) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Message must be between 1 and 32 characters.',
    );
  }

  const db = admin.firestore();
  const permission = await canUserControlPilotAlert({
    db,
    auth: context.auth,
    eventId,
    pilotUid,
    requestedTeamId,
  });
  if (!permission.allowed) {
    throw new functions.https.HttpsError(
      'permission-denied',
      `Not allowed to alert this pilot (${permission.reason}).`,
    );
  }

  const eventDoc = await db.collection('events').doc(eventId).get();
  if (!eventDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Event not found.');
  }
  const eventData = eventDoc.data() || {};
  const sessions = Array.isArray(eventData.sessions) ? eventData.sessions : [];
  const sessionExists = sessions.some((session) => session && session.id === sessionId);
  if (!sessionExists) {
    throw new functions.https.HttpsError('not-found', 'Session not found in event.');
  }

  const rateRef = db
    .collection('events')
    .doc(eventId)
    .collection('rate_limits')
    .doc(`pilot_alert_${context.auth.uid}`);
  const rateDoc = await rateRef.get();
  const nowMs = Date.now();
  const minIntervalMs = 1500;
  if (rateDoc.exists) {
    const rateData = rateDoc.data() || {};
    const lastSentAtMs = asFiniteNumber(rateData.last_sent_at_ms, null);
    if (lastSentAtMs !== null && nowMs - lastSentAtMs < minIntervalMs) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Too many alerts. Please wait a moment and try again.',
      );
    }
  }

  let expiresAtMs = null;
  const expiresInSeconds = asFiniteNumber(data.expiresInSeconds, null);
  if (expiresInSeconds !== null && expiresInSeconds > 0) {
    const boundedSeconds = Math.max(5, Math.min(300, Math.trunc(expiresInSeconds)));
    expiresAtMs = nowMs + boundedSeconds * 1000;
  }

  const actorName =
    (context.auth.token.name || context.auth.token.email || '').toString().trim();

  const alertRef = db
    .collection('events')
    .doc(eventId)
    .collection('sessions')
    .doc(sessionId)
    .collection('pilot_alerts')
    .doc(pilotUid);

  await alertRef.set(
    {
      active: true,
      event_id: eventId,
      session_id: sessionId,
      pilot_uid: pilotUid,
      message,
      type: type === 'box' ? 'box' : 'custom',
      team_id: permission.teamId || null,
      team_name: permission.teamName || null,
      created_by: context.auth.uid,
      created_by_name: actorName || null,
      updated_by: context.auth.uid,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      removed_at: null,
      removed_by: null,
      expires_at_ms: expiresAtMs,
    },
    { merge: true },
  );

  await rateRef.set(
    {
      key: `pilot_alert_${context.auth.uid}`,
      uid: context.auth.uid,
      last_sent_at_ms: nowMs,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    success: true,
    eventId,
    sessionId,
    pilotUid,
    message,
    type: type === 'box' ? 'box' : 'custom',
  };
});

exports.clearPilotAlert = functions.https.onCall(async (data, context) => {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }

  const eventId = (data.eventId || '').toString().trim();
  const sessionId = (data.sessionId || '').toString().trim();
  const pilotUid = (data.pilotUid || '').toString().trim();
  if (!eventId || !sessionId || !pilotUid) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'eventId, sessionId and pilotUid are required.',
    );
  }

  const db = admin.firestore();
  const alertRef = db
    .collection('events')
    .doc(eventId)
    .collection('sessions')
    .doc(sessionId)
    .collection('pilot_alerts')
    .doc(pilotUid);

  const alertDoc = await alertRef.get();
  if (!alertDoc.exists) {
    return {
      success: true,
      eventId,
      sessionId,
      pilotUid,
      alreadyCleared: true,
    };
  }

  const alertData = alertDoc.data() || {};
  let allowed = false;

  if (await isAdminUser(db, context.auth)) {
    allowed = true;
  } else if ((alertData.created_by || '').toString().trim() === context.auth.uid) {
    allowed = true;
  } else {
    const permission = await canUserControlPilotAlert({
      db,
      auth: context.auth,
      eventId,
      pilotUid,
      requestedTeamId: (alertData.team_id || '').toString().trim() || null,
    });
    allowed = permission.allowed;
  }

  if (!allowed) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Not allowed to clear this pilot alert.',
    );
  }

  await alertRef.set(
    {
      active: false,
      removed_by: context.auth.uid,
      removed_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_by: context.auth.uid,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    success: true,
    eventId,
    sessionId,
    pilotUid,
  };
});

exports.getPublicSessionResults = functions.https.onCall(async (data) => {
  const eventId = (data.eventId || '').toString().trim();
  const sessionId = (data.sessionId || '').toString().trim();
  if (!eventId || !sessionId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'eventId and sessionId are required.',
    );
  }

  const db = admin.firestore();
  const eventDoc = await db.collection('events').doc(eventId).get();
  if (!eventDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Event not found.');
  }

  const eventData = eventDoc.data() || {};
  const sessions = Array.isArray(eventData.sessions) ? eventData.sessions : [];
  const sessionEntry = sessions.find((entry) => entry && entry.id === sessionId);
  if (!sessionEntry) {
    throw new functions.https.HttpsError('not-found', 'Session not found.');
  }

  const sessionType = parseSessionType(sessionEntry.type);
  const sessionName =
    (sessionEntry.name || '').toString().trim() ||
    (sessionEntry.short_name || '').toString().trim() ||
    sessionType.toUpperCase();
  const minLapTimeSeconds = Math.max(
    0,
    Math.trunc(asFiniteNumber(sessionEntry.min_lap_time_seconds, DEFAULT_MIN_LAP_TIME_SECONDS)),
  );
  const minLapMs = minLapTimeSeconds * 1000;

  const competitorsSnap = await db
    .collection('events')
    .doc(eventId)
    .collection('competitors')
    .get();

  const competitorByUid = new Map();
  for (const doc of competitorsSnap.docs) {
    const competitor = doc.data() || {};
    const uid = (competitor.uid || competitor.user_id || '').toString().trim();
    if (!uid) continue;
    competitorByUid.set(uid, competitor);
  }

  const participantsSnap = await db
    .collection('events')
    .doc(eventId)
    .collection('sessions')
    .doc(sessionId)
    .collection('participants')
    .get();

  const rows = [];
  for (const participantDoc of participantsSnap.docs) {
    const uid = participantDoc.id;
    const competitor = competitorByUid.get(uid) || {};
    const lapsSnap = await participantDoc.ref.collection('laps').limit(1200).get();
    const laps = lapsSnap.docs.map((doc) => doc.data() || {});
    if (!laps.length) continue;

    const validLapTimes = [];
    for (const lap of laps) {
      const lapMs = asFiniteNumber(
        lap.total_lap_time_ms ?? lap.lap_time_ms ?? lap.lap_time,
        null,
      );
      const isValid = lap.valid !== false;
      if (!isValid || lapMs === null || lapMs <= 0) continue;
      if (minLapMs > 0 && lapMs < minLapMs) continue;
      validLapTimes.push(Math.trunc(lapMs));
    }

    const bestLapMs = validLapTimes.length ? Math.min(...validLapTimes) : null;
    const totalLaps = laps.length;
    const validLaps = validLapTimes.length;

    const firstName = (competitor.first_name || '').toString().trim();
    const lastName = (competitor.last_name || '').toString().trim();
    const displayName = `${firstName} ${lastName}`.trim() || `Pilot ${uid.slice(0, 6)}`;
    let teamName = (competitor.team_name || '').toString().trim();
    if (
      !teamName &&
      competitor.additional_fields &&
      typeof competitor.additional_fields === 'object'
    ) {
      teamName = (competitor.additional_fields.Team || '').toString().trim();
    }

    rows.push({
      uid,
      display_name: displayName,
      car_number: (competitor.number || '').toString().trim(),
      team_name: teamName,
      best_lap_ms: bestLapMs,
      valid_laps: validLaps,
      laps: totalLaps,
    });
  }

  rows.sort((a, b) => {
    if (sessionType === 'race') {
      if (b.laps !== a.laps) return b.laps - a.laps;
      if (a.best_lap_ms == null && b.best_lap_ms == null) {
        return a.display_name.localeCompare(b.display_name);
      }
      if (a.best_lap_ms == null) return 1;
      if (b.best_lap_ms == null) return -1;
      return a.best_lap_ms - b.best_lap_ms;
    }

    if (a.best_lap_ms == null && b.best_lap_ms == null) {
      return a.display_name.localeCompare(b.display_name);
    }
    if (a.best_lap_ms == null) return 1;
    if (b.best_lap_ms == null) return -1;
    return a.best_lap_ms - b.best_lap_ms;
  });

  const results = rows.map((row, index) => ({
    position: index + 1,
    ...row,
  }));

  return {
    success: true,
    event_id: eventId,
    session_id: sessionId,
    event_name: (eventData.name || '').toString().trim(),
    session_name: sessionName,
    session_type: sessionType,
    generated_at_ms: Date.now(),
    results,
  };
});

exports.clearSessionRuntimeData = functions.https.onCall(async (data, context) => {
  const db = admin.firestore();
  await assertAdminAccess(db, context.auth);

  const raceId = (data.raceId || '').toString().trim();
  const sessionId = (data.sessionId || '').toString().trim();
  const eventId = (data.eventId || '').toString().trim() || null;

  if (!raceId || !sessionId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'raceId and sessionId are required.',
    );
  }

  let deletedDocs = 0;

  async function deleteCollectionAndCount(collectionRef) {
    while (true) {
      const snapshot = await collectionRef.limit(350).get();
      if (snapshot.empty) break;
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      deletedDocs += snapshot.size;
      if (snapshot.size < 350) break;
    }
  }

  async function deleteQueryAndCount(query) {
    while (true) {
      const snapshot = await query.limit(350).get();
      if (snapshot.empty) break;
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      deletedDocs += snapshot.size;
      if (snapshot.size < 350) break;
    }
  }

  if (eventId) {
    const eventSessionRef = db
      .collection('events')
      .doc(eventId)
      .collection('sessions')
      .doc(sessionId);

    const eventParticipantsSnap = await eventSessionRef.collection('participants').get();
    for (const participantDoc of eventParticipantsSnap.docs) {
      await deleteCollectionAndCount(participantDoc.ref.collection('laps'));
      await deleteCollectionAndCount(participantDoc.ref.collection('crossings'));
      await deleteCollectionAndCount(participantDoc.ref.collection('analysis'));
      await deleteCollectionAndCount(participantDoc.ref.collection('state'));
      await participantDoc.ref.delete();
      deletedDocs += 1;
    }

    await deleteCollectionAndCount(eventSessionRef.collection('passings'));
    await deleteCollectionAndCount(eventSessionRef.collection('local_lap_closures'));
    await deleteCollectionAndCount(eventSessionRef.collection('analysis'));
  }

  const raceRef = db.collection('races').doc(raceId);

  await deleteQueryAndCount(
    raceRef.collection('passings').where('session_id', '==', sessionId),
  );
  await deleteQueryAndCount(
    raceRef.collection('local_lap_closures').where('session_id', '==', sessionId),
  );

  const raceParticipantsSnap = await raceRef.collection('participants').get();
  for (const participantDoc of raceParticipantsSnap.docs) {
    const sessionRef = participantDoc.ref.collection('sessions').doc(sessionId);
    await deleteCollectionAndCount(sessionRef.collection('laps'));
    await deleteCollectionAndCount(sessionRef.collection('crossings'));
    await deleteCollectionAndCount(sessionRef.collection('analysis'));
    await deleteCollectionAndCount(sessionRef.collection('state'));
    const sessionSnap = await sessionRef.get();
    if (sessionSnap.exists) {
      await sessionRef.delete();
      deletedDocs += 1;
    }
  }

  return {
    success: true,
    raceId,
    sessionId,
    eventId,
    deletedDocs,
  };
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
    const participantResult = await materializeParticipantSessionFromPassings({
      db,
      raceId,
      eventId,
      sessionId,
      uid,
      minLapMs,
      minLapTimeSeconds,
    });
    if (!participantResult.updated) {
      continue;
    }
    result.participantsUpdated += 1;
    result.lapsRebuilt += participantResult.lapsRebuilt;
    result.crossingsRebuilt += participantResult.crossingsRebuilt;
  }

  console.log(
    `Backfill completed for race=${raceId} session=${sessionId}: ` +
      `participantsUpdated=${result.participantsUpdated}, ` +
      `laps=${result.lapsRebuilt}, crossings=${result.crossingsRebuilt}`,
  );

  return result;
});
