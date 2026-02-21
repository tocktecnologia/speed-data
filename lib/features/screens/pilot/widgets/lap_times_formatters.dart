import 'dart:math' as math;

import 'package:flutter/material.dart';
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

String formatDeltaDurationMs(int? deltaMs, {String fallback = '-'}) {
  if (deltaMs == null) return fallback;
  if (deltaMs == 0) return '0:00.000';
  final abs = deltaMs.abs();
  final duration = Duration(milliseconds: abs);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final millis =
      duration.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  final sign = deltaMs > 0 ? '+' : '-';
  return '$sign$minutes:$seconds.$millis';
}

String formatDeltaSpeedMps(double? delta, {String fallback = '-'}) {
  if (delta == null) return fallback;
  if (delta == 0) return '0.0 m/s';
  final sign = delta > 0 ? '+' : '-';
  return '$sign${delta.abs().toStringAsFixed(1)} m/s';
}

bool isLapValid(LapAnalysisModel lap, {int minLapTimeMs = 0}) {
  if (!lap.valid || lap.totalLapTimeMs <= 0) return false;
  if (minLapTimeMs > 0 && lap.totalLapTimeMs < minLapTimeMs) return false;
  return true;
}

LapAnalysisModel? selectReferenceLap(
  List<LapAnalysisModel> laps, {
  int minLapTimeMs = 0,
  String? preferredLapId,
}) {
  if (preferredLapId != null && preferredLapId.isNotEmpty) {
    final preferred = laps.cast<LapAnalysisModel?>().firstWhere(
          (lap) => lap?.id == preferredLapId,
          orElse: () => null,
        );
    if (preferred != null) {
      return preferred;
    }
  }

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
  final validLaps = laps
      .where((lap) => isLapValid(lap, minLapTimeMs: minLapTimeMs))
      .toList(growable: false);
  if (validLaps.isEmpty) {
    if (summary != null && summary.bestSectorsMs.isNotEmpty) {
      return summary.bestSectorsMs
          .where((value) => value > 0)
          .toList(growable: false);
    }
    return const [];
  }

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

Color durationDeltaColor(
  ColorScheme scheme, {
  required int? currentValue,
  required int? referenceValue,
}) {
  if (currentValue == null || referenceValue == null) {
    return scheme.onSurface;
  }
  if (currentValue <= 0 || referenceValue <= 0) {
    return scheme.onSurfaceVariant;
  }
  final delta = currentValue - referenceValue;
  if (delta < 0) return Colors.green.shade400;
  if (delta > 0) return Colors.red.shade400;
  return scheme.primary;
}

Color speedDeltaColor(
  ColorScheme scheme, {
  required double? currentValue,
  required double? referenceValue,
}) {
  if (currentValue == null || referenceValue == null) {
    return scheme.onSurface;
  }
  if (currentValue <= 0 || referenceValue <= 0) {
    return scheme.onSurfaceVariant;
  }
  final delta = currentValue - referenceValue;
  if (delta > 0) return Colors.green.shade400;
  if (delta < 0) return Colors.red.shade400;
  return scheme.primary;
}

Color speedGradientColor(double speedMps) {
  if (!speedMps.isFinite || speedMps <= 0) return Colors.red.shade700;
  final kmh = speedMps * 3.6;
  if (kmh <= 100) {
    final t = (kmh / 100).clamp(0.0, 1.0).toDouble();
    return Color.lerp(Colors.red, Colors.yellow, t)!;
  }
  if (kmh <= 200) {
    final t = ((kmh - 100) / 100).clamp(0.0, 1.0).toDouble();
    return Color.lerp(Colors.yellow, Colors.green, t)!;
  }
  final t = ((kmh - 200) / 100).clamp(0.0, 1.0).toDouble();
  return Color.lerp(Colors.green, Colors.cyan, t)!;
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
