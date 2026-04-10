const DEFAULT_MIN_LAP_TIME_SECONDS = 15;
const DEFAULT_DEDUP_WINDOW_MS = 400;
const DEFAULT_TRAP_WIDTH_M = 50;

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

function metersPerDegree(latDeg) {
  const latRad = (Number(latDeg) || 0) * (Math.PI / 180);
  // Good enough approximation for short segments in a race track.
  return {
    lat: 111132.92,
    lng: 111412.84 * Math.cos(latRad),
  };
}

function pointToLocalMeters(point, center) {
  if (!point || !center) return null;
  const lat = Number(point.lat);
  const lng = Number(point.lng);
  const cLat = Number(center.lat);
  const cLng = Number(center.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !Number.isFinite(cLat) || !Number.isFinite(cLng)) {
    return null;
  }
  const m = metersPerDegree(cLat);
  return {
    x: (lng - cLng) * m.lng,
    y: (lat - cLat) * m.lat,
  };
}

function normalizeVec2(v) {
  if (!v) return null;
  const x = Number(v.x);
  const y = Number(v.y);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  const len = Math.hypot(x, y);
  if (!Number.isFinite(len) || len < 1e-6) return null;
  return { x: x / len, y: y / len };
}

function buildCheckpointLines(checkpoints = [], trapWidthM = DEFAULT_TRAP_WIDTH_M) {
  if (!Array.isArray(checkpoints) || checkpoints.length < 2) return [];
  const sanitized = checkpoints.map((cp) => ({
    lat: Number(cp && cp.lat),
    lng: Number(cp && cp.lng),
  }));

  const lines = [];
  for (let i = 0; i < sanitized.length; i++) {
    const center = sanitized[i];
    if (!Number.isFinite(center.lat) || !Number.isFinite(center.lng)) {
      lines.push(null);
      continue;
    }

    const prev = i > 0 ? sanitized[i - 1] : sanitized[i];
    const next = i < sanitized.length - 1 ? sanitized[i + 1] : sanitized[i];
    const prevLocal = pointToLocalMeters(prev, center);
    const nextLocal = pointToLocalMeters(next, center);
    let tangent = null;
    if (prevLocal && nextLocal) {
      tangent = {
        x: nextLocal.x - prevLocal.x,
        y: nextLocal.y - prevLocal.y,
      };
    }

    let normalUnit = normalizeVec2(tangent);
    if (!normalUnit) {
      // Fallback direction if checkpoints collapse in the same spot.
      normalUnit = { x: 1, y: 0 };
    }
    const lineUnit = { x: -normalUnit.y, y: normalUnit.x };

    lines.push({
      index: i,
      center,
      normalUnit,
      lineUnit,
      halfWidthM: Math.max(1, Number(trapWidthM) || DEFAULT_TRAP_WIDTH_M) / 2,
    });
  }
  return lines.filter(Boolean);
}

function estimateTimeFractionWithConstantAcceleration(alpha, pointA, pointB) {
  const clampedAlpha = Math.max(0, Math.min(1, Number(alpha) || 0));
  const t0Ms = Number(pointA && pointA.timestamp);
  const t1Ms = Number(pointB && pointB.timestamp);
  if (!Number.isFinite(t0Ms) || !Number.isFinite(t1Ms) || t1Ms <= t0Ms) {
    return clampedAlpha;
  }

  const dtSec = (t1Ms - t0Ms) / 1000;
  const v0 = Number(pointA && pointA.speed);
  const v1 = Number(pointB && pointB.speed);
  if (
    !Number.isFinite(v0) ||
    !Number.isFinite(v1) ||
    v0 < 0 ||
    v1 < 0 ||
    dtSec <= 1e-9
  ) {
    return clampedAlpha;
  }

  const accel = (v1 - v0) / dtSec;
  const totalDistanceM = ((v0 + v1) / 2) * dtSec;
  if (!Number.isFinite(totalDistanceM) || totalDistanceM <= 1e-6) {
    return clampedAlpha;
  }
  const targetDistanceM = clampedAlpha * totalDistanceM;

  const linearTimeSec = clampedAlpha * dtSec;
  let crossingTimeSec = null;

  if (Math.abs(accel) <= 1e-6) {
    if (v0 > 1e-6) {
      crossingTimeSec = targetDistanceM / v0;
    }
  } else {
    const qa = 0.5 * accel;
    const qb = v0;
    const qc = -targetDistanceM;
    const discriminant = qb * qb - 4 * qa * qc;
    if (Number.isFinite(discriminant) && discriminant >= -1e-6) {
      const safeDiscriminant = Math.max(0, discriminant);
      const sqrtDisc = Math.sqrt(safeDiscriminant);
      const denom = 2 * qa;
      if (Math.abs(denom) > 1e-12) {
        const r1 = (-qb + sqrtDisc) / denom;
        const r2 = (-qb - sqrtDisc) / denom;
        const inRange = (v) => Number.isFinite(v) && v >= -1e-6 && v <= dtSec + 1e-6;
        const c1 = inRange(r1) ? r1 : null;
        const c2 = inRange(r2) ? r2 : null;
        if (c1 !== null && c2 !== null) {
          crossingTimeSec =
            Math.abs(c1 - linearTimeSec) <= Math.abs(c2 - linearTimeSec) ? c1 : c2;
        } else if (c1 !== null) {
          crossingTimeSec = c1;
        } else if (c2 !== null) {
          crossingTimeSec = c2;
        }
      }
    }
  }

  if (!Number.isFinite(crossingTimeSec)) {
    return clampedAlpha;
  }
  return Math.max(0, Math.min(1, crossingTimeSec / dtSec));
}

function interpolateLineCrossing(line, pointA, pointB) {
  if (!line || !pointA || !pointB) return null;

  const t0 = Number(pointA.timestamp);
  const t1 = Number(pointB.timestamp);
  if (!Number.isFinite(t0) || !Number.isFinite(t1) || t1 < t0) return null;

  const localA = pointToLocalMeters(pointA, line.center);
  const localB = pointToLocalMeters(pointB, line.center);
  if (!localA || !localB) return null;

  const signedA = localA.x * line.normalUnit.x + localA.y * line.normalUnit.y;
  const signedB = localB.x * line.normalUnit.x + localB.y * line.normalUnit.y;

  const eps = 1e-9;
  const bothOnLine = Math.abs(signedA) <= eps && Math.abs(signedB) <= eps;
  if (bothOnLine) return null;

  if (signedA * signedB > 0 && Math.abs(signedA) > eps && Math.abs(signedB) > eps) {
    return null;
  }

  const denom = signedB - signedA;
  if (Math.abs(denom) <= eps) {
    return null;
  }

  const alpha = -signedA / denom;
  if (!Number.isFinite(alpha) || alpha < 0 || alpha > 1) {
    return null;
  }

  const alongA = localA.x * line.lineUnit.x + localA.y * line.lineUnit.y;
  const alongB = localB.x * line.lineUnit.x + localB.y * line.lineUnit.y;
  const alongCross = alongA + (alongB - alongA) * alpha;
  if (Math.abs(alongCross) > line.halfWidthM) {
    return null;
  }

  const interp = (a, b, fallback = 0) => {
    const av = Number(a);
    const bv = Number(b);
    if (Number.isFinite(av) && Number.isFinite(bv)) {
      return av + (bv - av) * alpha;
    }
    if (Number.isFinite(av)) return av;
    if (Number.isFinite(bv)) return bv;
    return fallback;
  };

  const temporalAlpha = estimateTimeFractionWithConstantAcceleration(
    alpha,
    pointA,
    pointB,
  );
  const interpByTime = (a, b, fallback = 0) => {
    const av = Number(a);
    const bv = Number(b);
    if (Number.isFinite(av) && Number.isFinite(bv)) {
      return av + (bv - av) * temporalAlpha;
    }
    if (Number.isFinite(av)) return av;
    if (Number.isFinite(bv)) return bv;
    return fallback;
  };

  return {
    checkpointIndex: line.index,
    timestamp: Math.trunc(interpByTime(t0, t1, t0)),
    lat: interp(pointA.lat, pointB.lat),
    lng: interp(pointA.lng, pointB.lng),
    speed: interpByTime(pointA.speed, pointB.speed, 0),
    heading: interpByTime(pointA.heading, pointB.heading, 0),
    altitude: interpByTime(pointA.altitude, pointB.altitude, 0),
    alpha,
    temporal_alpha: temporalAlpha,
    line_offset_m: alongCross,
    method: 'line_interpolation',
    confidence: 0.97,
  };
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

    let split = Number(passing.split_time ?? passing.split_time_ms);
    if (!Number.isFinite(split) || split < 0) {
      const lapTimeAsSplit = Number(passing.lap_time);
      if (Number.isFinite(lapTimeAsSplit) && lapTimeAsSplit >= 0) {
        split = lapTimeAsSplit;
      }
    }
    if (Number.isFinite(split) && split >= 0) {
      splitsByCheckpoint[checkpointIndex] = split;
    }

    const sector = Number(passing.sector_time ?? passing.sector_time_ms);
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

  // Derive missing sector values from adjacent split deltas.
  for (const checkpointIndex of splitKeys) {
    if (checkpointIndex <= 0) continue;
    const existingSector = Number(sectorsByCheckpoint[checkpointIndex]);
    if (Number.isFinite(existingSector) && existingSector >= 0) {
      continue;
    }
    const split = Number(splitsByCheckpoint[checkpointIndex]);
    const previousSplit = Number(splitsByCheckpoint[checkpointIndex - 1]);
    if (!Number.isFinite(split) || !Number.isFinite(previousSplit)) {
      continue;
    }
    if (split < previousSplit) {
      continue;
    }
    sectorsByCheckpoint[checkpointIndex] = split - previousSplit;
  }

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
  DEFAULT_TRAP_WIDTH_M,
  toMillis,
  normalizeFlags,
  computeSpeedStats,
  buildCheckpointLines,
  interpolateLineCrossing,
  shouldSkipCheckpointCrossing,
  buildLapPayloadFromState,
  buildLapPayloadFromPassings,
  buildSessionSummaryFromLaps,
};
