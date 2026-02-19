const DEFAULT_MIN_LAP_TIME_SECONDS = 15;
const DEFAULT_DEDUP_WINDOW_MS = 400;

function toMillis(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const parsedNum = Number(value);
    if (Number.isFinite(parsedNum)) return Math.trunc(parsedNum);
    const parsedDate = Date.parse(value);
    if (Number.isFinite(parsedDate)) return parsedDate;
    return null;
  }
  if (typeof value === 'object' && typeof value.toMillis === 'function') {
    const parsed = value.toMillis();
    return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
  }
  if (typeof value === 'object' && typeof value.seconds === 'number') {
    const nanos = typeof value.nanoseconds === 'number' ? value.nanoseconds : 0;
    return Math.trunc(value.seconds * 1000 + nanos / 1e6);
  }
  return null;
}

function normalizeFlags(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((flag) => (flag || '').toString().trim().toLowerCase())
    .filter((flag) => flag.length > 0);
}

function computeSpeedStats(speeds = []) {
  if (!Array.isArray(speeds) || !speeds.length) return null;
  const filtered = speeds
    .map((speed) => Number(speed))
    .filter((speed) => Number.isFinite(speed) && speed > 0);
  if (!filtered.length) return null;
  const min = Math.min(...filtered);
  const max = Math.max(...filtered);
  const avg = filtered.reduce((sum, speed) => sum + speed, 0) / filtered.length;
  return { min_mps: min, max_mps: max, avg_mps: avg };
}

function shouldSkipCheckpointCrossing({
  lastCheckpointIndex,
  checkpointIndex,
  lastCrossedAtMs,
  crossedAtMs,
  finishCheckpointIndex,
  dedupWindowMs = DEFAULT_DEDUP_WINDOW_MS,
}) {
  const sameCheckpoint = lastCheckpointIndex === checkpointIndex;
  const tooSoon =
    Number.isFinite(lastCrossedAtMs) &&
    Number.isFinite(crossedAtMs) &&
    crossedAtMs - lastCrossedAtMs < dedupWindowMs &&
    sameCheckpoint;
  const wrappedStart =
    lastCheckpointIndex === finishCheckpointIndex && checkpointIndex === 0;
  const outOfOrder =
    !wrappedStart &&
    checkpointIndex !== finishCheckpointIndex &&
    Number.isFinite(lastCheckpointIndex) &&
    lastCheckpointIndex > checkpointIndex;
  return tooSoon || outOfOrder;
}

function buildLapPayloadFromState({
  lapNumber,
  lapStartMs,
  lapEndMs,
  checkpointTimes,
  checkpointSpeeds,
  minLapMs = DEFAULT_MIN_LAP_TIME_SECONDS * 1000,
  minLapTimeSeconds = DEFAULT_MIN_LAP_TIME_SECONDS,
}) {
  if (!Number.isFinite(lapStartMs) || !Number.isFinite(lapEndMs) || lapEndMs <= lapStartMs) {
    return null;
  }

  const totalLapTimeMs = lapEndMs - lapStartMs;
  const valid = totalLapTimeMs >= minLapMs;
  const invalidReasons = valid ? [] : [`min_lap_time_seconds_${minLapTimeSeconds}`];

  const safeTimes = checkpointTimes && typeof checkpointTimes === 'object' ? checkpointTimes : {};
  const safeSpeeds = checkpointSpeeds && typeof checkpointSpeeds === 'object' ? checkpointSpeeds : {};
  const checkpointIndices = Object.keys(safeTimes)
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value))
    .sort((a, b) => a - b);

  const splitsMs = [];
  const sectorsMs = [];
  const trapSpeedsMps = [];
  let previousTs = lapStartMs;

  for (const checkpointIndex of checkpointIndices) {
    const checkpointTs = Number(safeTimes[checkpointIndex]);
    if (!Number.isFinite(checkpointTs)) continue;
    splitsMs.push(checkpointTs - lapStartMs);
    if (checkpointIndex !== 0) {
      sectorsMs.push(checkpointTs - previousTs);
    }
    previousTs = checkpointTs;
    const speed = Number(safeSpeeds[checkpointIndex]);
    if (Number.isFinite(speed) && speed > 0) {
      trapSpeedsMps.push(speed);
    }
  }

  return {
    number: Number.isFinite(lapNumber) ? Math.trunc(lapNumber) : 0,
    lap_start_ms: lapStartMs,
    lap_end_ms: lapEndMs,
    total_lap_time_ms: totalLapTimeMs,
    splits_ms: splitsMs,
    sectors_ms: sectorsMs,
    trap_speeds_mps: trapSpeedsMps,
    speed_stats: computeSpeedStats(trapSpeedsMps),
    valid,
    invalid_reasons: invalidReasons,
  };
}

function buildLapPayloadFromPassings({
  lapNumber,
  passings,
  minLapMs = DEFAULT_MIN_LAP_TIME_SECONDS * 1000,
  minLapTimeSeconds = DEFAULT_MIN_LAP_TIME_SECONDS,
}) {
  if (!Array.isArray(passings) || !passings.length) return null;
  const sorted = [...passings].sort((a, b) => {
    const at = toMillis(a.timestamp) || 0;
    const bt = toMillis(b.timestamp) || 0;
    return at - bt;
  });

  const closing = [...sorted]
    .reverse()
    .find((passing) => Number.isFinite(Number(passing.lap_time)) && Number(passing.lap_time) > 0);
  if (!closing) return null;

  const lapEndMs = toMillis(closing.timestamp);
  const totalLapTimeMs = Number(closing.lap_time);
  if (!Number.isFinite(lapEndMs) || !Number.isFinite(totalLapTimeMs) || totalLapTimeMs <= 0) {
    return null;
  }
  const lapStartMs = lapEndMs - totalLapTimeMs;

  const splitsByCheckpoint = {};
  const sectorsByCheckpoint = {};
  const trapByCheckpoint = {};
  const allFlags = new Set();

  for (const passing of sorted) {
    const checkpointIndex = Number(passing.checkpoint_index);
    if (!Number.isFinite(checkpointIndex) || checkpointIndex < 0) continue;

    const split = Number(passing.split_time);
    if (Number.isFinite(split) && split >= 0) {
      splitsByCheckpoint[checkpointIndex] = split;
    }

    const sector = Number(passing.sector_time);
    if (Number.isFinite(sector) && sector >= 0 && checkpointIndex > 0) {
      sectorsByCheckpoint[checkpointIndex] = sector;
    }

    const trap = Number(passing.trap_speed ?? passing.speed_mps);
    if (Number.isFinite(trap) && trap > 0) {
      trapByCheckpoint[checkpointIndex] = trap;
    }

    for (const flag of normalizeFlags(passing.flags)) {
      allFlags.add(flag);
    }
  }

  const splitKeys = Object.keys(splitsByCheckpoint)
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value))
    .sort((a, b) => a - b);
  const sectorKeys = Object.keys(sectorsByCheckpoint)
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value))
    .sort((a, b) => a - b);
  const trapKeys = Object.keys(trapByCheckpoint)
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value))
    .sort((a, b) => a - b);

  const splitsMs = splitKeys.map((key) => Number(splitsByCheckpoint[key]));
  const sectorsMs = sectorKeys.map((key) => Number(sectorsByCheckpoint[key]));
  const trapSpeedsMps = trapKeys.map((key) => Number(trapByCheckpoint[key]));

  let valid = totalLapTimeMs >= minLapMs;
  const invalidReasons = [];
  if (!valid) {
    invalidReasons.push(`min_lap_time_seconds_${minLapTimeSeconds}`);
  }
  if (allFlags.has('invalid')) {
    valid = false;
    invalidReasons.push('flag_invalid');
  }
  if (allFlags.has('deleted')) {
    valid = false;
    invalidReasons.push('flag_deleted');
  }

  return {
    number: Number.isFinite(lapNumber) ? Math.trunc(lapNumber) : 0,
    lap_start_ms: lapStartMs,
    lap_end_ms: lapEndMs,
    total_lap_time_ms: Math.trunc(totalLapTimeMs),
    splits_ms: splitsMs,
    sectors_ms: sectorsMs,
    trap_speeds_mps: trapSpeedsMps,
    speed_stats: computeSpeedStats(trapSpeedsMps),
    valid,
    invalid_reasons: [...new Set(invalidReasons)],
  };
}

function buildSessionSummaryFromLaps(laps = []) {
  const sorted = [...laps].sort((a, b) => a.number - b.number);
  let bestLapMs = null;
  const bestSectorsByIndex = {};
  let validLapsCount = 0;

  for (const lap of sorted) {
    if (!lap || lap.valid !== true || !Number.isFinite(lap.total_lap_time_ms) || lap.total_lap_time_ms <= 0) {
      continue;
    }
    validLapsCount += 1;
    if (bestLapMs === null || lap.total_lap_time_ms < bestLapMs) {
      bestLapMs = lap.total_lap_time_ms;
    }

    const sectors = Array.isArray(lap.sectors_ms) ? lap.sectors_ms : [];
    for (let i = 0; i < sectors.length; i++) {
      const value = Number(sectors[i]);
      if (!Number.isFinite(value) || value <= 0) continue;
      const sectorIndex = i + 1;
      if (!bestSectorsByIndex[sectorIndex] || value < bestSectorsByIndex[sectorIndex]) {
        bestSectorsByIndex[sectorIndex] = value;
      }
    }
  }

  const bestSectorIndexes = Object.keys(bestSectorsByIndex)
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value))
    .sort((a, b) => a - b);
  const bestSectorsMs = bestSectorIndexes.map((idx) => bestSectorsByIndex[idx]);
  const optimalLapMs = bestSectorsMs.length
    ? bestSectorsMs.reduce((sum, value) => sum + value, 0)
    : null;

  return {
    best_lap_ms: bestLapMs,
    optimal_lap_ms: optimalLapMs,
    best_sectors_ms: bestSectorsMs,
    valid_laps_count: validLapsCount,
    total_laps_count: sorted.length,
  };
}

module.exports = {
  DEFAULT_DEDUP_WINDOW_MS,
  DEFAULT_MIN_LAP_TIME_SECONDS,
  toMillis,
  normalizeFlags,
  computeSpeedStats,
  shouldSkipCheckpointCrossing,
  buildLapPayloadFromState,
  buildLapPayloadFromPassings,
  buildSessionSummaryFromLaps,
};
