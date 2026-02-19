const test = require('node:test');
const assert = require('node:assert/strict');

const {
  DEFAULT_TRAP_WIDTH_M,
  buildCheckpointLines,
  interpolateLineCrossing,
  shouldSkipCheckpointCrossing,
  buildLapPayloadFromState,
  buildLapPayloadFromPassings,
  buildSessionSummaryFromLaps,
} = require('../lap_analysis_utils');

test('shouldSkipCheckpointCrossing ignores duplicate checkpoint inside dedup window', () => {
  const skip = shouldSkipCheckpointCrossing({
    lastCheckpointIndex: 2,
    checkpointIndex: 2,
    lastCrossedAtMs: 10000,
    crossedAtMs: 10200,
    finishCheckpointIndex: 4,
    dedupWindowMs: 400,
  });
  assert.equal(skip, true);
});

test('shouldSkipCheckpointCrossing rejects out-of-order checkpoints but allows lap wrap', () => {
  const outOfOrder = shouldSkipCheckpointCrossing({
    lastCheckpointIndex: 3,
    checkpointIndex: 1,
    lastCrossedAtMs: 15000,
    crossedAtMs: 18000,
    finishCheckpointIndex: 4,
    dedupWindowMs: 400,
  });
  assert.equal(outOfOrder, true);

  const wrappedStart = shouldSkipCheckpointCrossing({
    lastCheckpointIndex: 4,
    checkpointIndex: 0,
    lastCrossedAtMs: 20000,
    crossedAtMs: 26000,
    finishCheckpointIndex: 4,
    dedupWindowMs: 400,
  });
  assert.equal(wrappedStart, false);
});

test('buildLapPayloadFromState computes splits/sectors and min-lap invalidation', () => {
  const payload = buildLapPayloadFromState({
    lapNumber: 7,
    lapStartMs: 1000,
    lapEndMs: 51000,
    checkpointTimes: { 0: 1000, 1: 21000, 2: 51000 },
    checkpointSpeeds: { 0: 32.1, 1: 35.4, 2: 36.9 },
    minLapMs: 60000,
    minLapTimeSeconds: 60,
  });

  assert.ok(payload);
  assert.equal(payload.number, 7);
  assert.equal(payload.total_lap_time_ms, 50000);
  assert.deepEqual(payload.splits_ms, [0, 20000, 50000]);
  assert.deepEqual(payload.sectors_ms, [20000, 30000]);
  assert.deepEqual(payload.trap_speeds_mps, [32.1, 35.4, 36.9]);
  assert.equal(payload.valid, false);
  assert.deepEqual(payload.invalid_reasons, ['min_lap_time_seconds_60']);
});

test('buildLapPayloadFromPassings rebuilds lap analytics from session passings', () => {
  const passings = [
    {
      lap_number: 3,
      checkpoint_index: 0,
      timestamp: { seconds: 100, nanoseconds: 0 },
      split_time: 0,
      trap_speed: 30.0,
      flags: [],
    },
    {
      lap_number: 3,
      checkpoint_index: 1,
      timestamp: { seconds: 120, nanoseconds: 0 },
      split_time: 20000,
      sector_time: 20000,
      trap_speed: 33.2,
      flags: [],
    },
    {
      lap_number: 3,
      checkpoint_index: 2,
      timestamp: { seconds: 155, nanoseconds: 0 },
      split_time: 55000,
      sector_time: 35000,
      trap_speed: 36.7,
      lap_time: 55000,
      flags: [],
    },
  ];

  const payload = buildLapPayloadFromPassings({
    lapNumber: 3,
    passings,
    minLapMs: 5000,
    minLapTimeSeconds: 5,
  });

  assert.ok(payload);
  assert.equal(payload.number, 3);
  assert.equal(payload.total_lap_time_ms, 55000);
  assert.equal(payload.lap_start_ms, 100000);
  assert.equal(payload.lap_end_ms, 155000);
  assert.deepEqual(payload.splits_ms, [0, 20000, 55000]);
  assert.deepEqual(payload.sectors_ms, [20000, 35000]);
  assert.deepEqual(payload.trap_speeds_mps, [30.0, 33.2, 36.7]);
  assert.equal(payload.valid, true);
});

test('buildSessionSummaryFromLaps uses only valid laps to compute best and optimal', () => {
  const summary = buildSessionSummaryFromLaps([
    {
      number: 1,
      valid: true,
      total_lap_time_ms: 62000,
      sectors_ms: [30000, 32000],
    },
    {
      number: 2,
      valid: false,
      total_lap_time_ms: 58000,
      sectors_ms: [28000, 30000],
    },
    {
      number: 3,
      valid: true,
      total_lap_time_ms: 60000,
      sectors_ms: [29000, 31000],
    },
  ]);

  assert.equal(summary.best_lap_ms, 60000);
  assert.equal(summary.optimal_lap_ms, 60000);
  assert.deepEqual(summary.best_sectors_ms, [29000, 31000]);
  assert.equal(summary.valid_laps_count, 2);
  assert.equal(summary.total_laps_count, 3);
});

test('buildCheckpointLines creates virtual line definitions with default width', () => {
  const checkpoints = [
    { lat: 0, lng: 0 },
    { lat: 0, lng: 0.001 },
    { lat: 0, lng: 0.002 },
  ];
  const lines = buildCheckpointLines(checkpoints);
  assert.equal(lines.length, checkpoints.length);
  assert.equal(lines[1].index, 1);
  assert.equal(lines[1].halfWidthM, DEFAULT_TRAP_WIDTH_M / 2);
  assert.ok(Number.isFinite(lines[1].normalUnit.x));
  assert.ok(Number.isFinite(lines[1].normalUnit.y));
  assert.ok(Number.isFinite(lines[1].lineUnit.x));
  assert.ok(Number.isFinite(lines[1].lineUnit.y));
});

test('interpolateLineCrossing returns interpolated crossing when segment crosses virtual line', () => {
  const checkpoints = [
    { lat: 0, lng: 0 },
    { lat: 0, lng: 0.001 },
    { lat: 0, lng: 0.002 },
  ];
  const line = buildCheckpointLines(checkpoints)[1];

  const crossing = interpolateLineCrossing(
    line,
    {
      lat: 0,
      lng: 0.0009,
      speed: 30,
      timestamp: 1000,
    },
    {
      lat: 0,
      lng: 0.0011,
      speed: 40,
      timestamp: 2000,
    },
  );

  assert.ok(crossing);
  assert.equal(crossing.checkpointIndex, 1);
  assert.equal(crossing.method, 'line_interpolation');
  assert.equal(crossing.timestamp, 1500);
  assert.ok(Math.abs(crossing.lng - 0.001) < 1e-8);
  assert.ok(Math.abs(crossing.speed - 35) < 0.0001);
});

test('interpolateLineCrossing rejects crossings outside trap width', () => {
  const checkpoints = [
    { lat: 0, lng: 0 },
    { lat: 0, lng: 0.001 },
    { lat: 0, lng: 0.002 },
  ];
  const line = buildCheckpointLines(checkpoints)[1];

  const notCrossing = interpolateLineCrossing(
    line,
    {
      lat: 0.001,
      lng: 0.0009,
      speed: 30,
      timestamp: 1000,
    },
    {
      lat: 0.001,
      lng: 0.0011,
      speed: 40,
      timestamp: 2000,
    },
  );

  assert.equal(notCrossing, null);
});
