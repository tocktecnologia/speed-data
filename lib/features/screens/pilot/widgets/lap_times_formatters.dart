import 'dart:math' as math;

import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';

String formatDurationMs(int? value, {String fallback = '-'}) {
  if (value == null || value <= 0) return fallback;
  final duration = Duration(milliseconds: value);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final millis =
      duration.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  return '$minutes:$seconds.$millis';
}

String formatSpeedMps(double? value, {String fallback = '-'}) {
  if (value == null || value <= 0) return fallback;
  return '${value.toStringAsFixed(1)} m/s';
}

bool isLapValid(LapAnalysisModel lap, {int minLapTimeMs = 0}) {
  if (!lap.valid || lap.totalLapTimeMs <= 0) return false;
  if (minLapTimeMs > 0 && lap.totalLapTimeMs < minLapTimeMs) return false;
  return true;
}

LapAnalysisModel? selectReferenceLap(
  List<LapAnalysisModel> laps, {
  int minLapTimeMs = 0,
}) {
  LapAnalysisModel? best;
  for (final lap in laps) {
    if (!isLapValid(lap, minLapTimeMs: minLapTimeMs)) continue;
    if (best == null || lap.totalLapTimeMs < best.totalLapTimeMs) {
      best = lap;
    }
  }
  return best;
}

int maxListLength<T>(List<List<T>> lists) {
  int maxLen = 0;
  for (final list in lists) {
    maxLen = math.max(maxLen, list.length);
  }
  return maxLen;
}

List<int> deriveOptimalSectors(
  List<LapAnalysisModel> laps, {
  SessionAnalysisSummaryModel? summary,
  int minLapTimeMs = 0,
}) {
  if (summary != null && summary.bestSectorsMs.isNotEmpty) {
    return summary.bestSectorsMs
        .where((value) => value > 0)
        .toList(growable: false);
  }

  final validLaps = laps
      .where((lap) => isLapValid(lap, minLapTimeMs: minLapTimeMs))
      .toList(growable: false);
  if (validLaps.isEmpty) return const [];

  final maxSectors = maxListLength(
      validLaps.map((lap) => lap.sectorsMs).toList(growable: false));
  final best = <int>[];
  for (int i = 0; i < maxSectors; i++) {
    int? bestSector;
    for (final lap in validLaps) {
      if (i >= lap.sectorsMs.length) continue;
      final value = lap.sectorsMs[i];
      if (value <= 0) continue;
      if (bestSector == null || value < bestSector) {
        bestSector = value;
      }
    }
    if (bestSector != null) {
      best.add(bestSector);
    }
  }
  return best;
}

List<CrossingModel> sortCrossingsByTime(List<CrossingModel> crossings) {
  final sorted = List<CrossingModel>.from(crossings)
    ..sort((a, b) => a.crossedAtMs.compareTo(b.crossedAtMs));
  return sorted;
}

double? deriveSpeedLow(LapAnalysisModel lap) {
  final stats = lap.speedStats;
  if (stats != null && stats.minMps > 0) return stats.minMps;
  if (lap.trapSpeedsMps.isEmpty) return null;
  return lap.trapSpeedsMps.reduce(math.min);
}

double? deriveSpeedHigh(LapAnalysisModel lap) {
  final stats = lap.speedStats;
  if (stats != null && stats.maxMps > 0) return stats.maxMps;
  if (lap.trapSpeedsMps.isEmpty) return null;
  return lap.trapSpeedsMps.reduce(math.max);
}

double? deriveSpeedAvg(LapAnalysisModel lap) {
  final stats = lap.speedStats;
  if (stats != null && stats.avgMps > 0) return stats.avgMps;
  if (lap.trapSpeedsMps.isEmpty) return null;
  final sum = lap.trapSpeedsMps.fold<double>(0, (acc, value) => acc + value);
  return sum / lap.trapSpeedsMps.length;
}
