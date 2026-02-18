class LapAnalysisModel {
  final String id;
  final int number;
  final int lapStartMs;
  final int lapEndMs;
  final int totalLapTimeMs;
  final bool valid;
  final List<String> invalidReasons;
  final List<int> splitsMs;
  final List<int> sectorsMs;
  final List<double> trapSpeedsMps;
  final SpeedStats? speedStats;
  final double? distanceM;
  final int? createdAtMs;

  LapAnalysisModel({
    required this.id,
    required this.number,
    required this.lapStartMs,
    required this.lapEndMs,
    required this.totalLapTimeMs,
    required this.valid,
    required this.invalidReasons,
    required this.splitsMs,
    required this.sectorsMs,
    required this.trapSpeedsMps,
    this.speedStats,
    this.distanceM,
    this.createdAtMs,
  });

  factory LapAnalysisModel.fromMap(String id, Map<String, dynamic> map) {
    num _num(dynamic v, num fallback) => v is num ? v : fallback;

    List<int> _intList(dynamic v) {
      if (v is List) {
        return v.whereType<num>().map((e) => e.toInt()).toList();
      }
      return const [];
    }

    List<double> _doubleList(dynamic v) {
      if (v is List) {
        return v.whereType<num>().map((e) => e.toDouble()).toList();
      }
      return const [];
    }

    SpeedStats? _stats(Map<String, dynamic>? m) {
      if (m == null) return null;
      return SpeedStats(
        minMps: _num(m['min_mps'], 0).toDouble(),
        maxMps: _num(m['max_mps'], 0).toDouble(),
        avgMps: _num(m['avg_mps'], 0).toDouble(),
      );
    }

    return LapAnalysisModel(
      id: id,
      number: map['number'] is num ? (map['number'] as num).toInt() : 0,
      lapStartMs: map['lap_start_ms'] is num ? (map['lap_start_ms'] as num).toInt() : 0,
      lapEndMs: map['lap_end_ms'] is num ? (map['lap_end_ms'] as num).toInt() : 0,
      totalLapTimeMs:
          map['total_lap_time_ms'] is num ? (map['total_lap_time_ms'] as num).toInt() : 0,
      valid: map['valid'] == true,
      invalidReasons: List<String>.from(map['invalid_reasons'] ?? const []),
      splitsMs: _intList(map['splits_ms']),
      sectorsMs: _intList(map['sectors_ms']),
      trapSpeedsMps: _doubleList(map['trap_speeds_mps']),
      speedStats: _stats(map['speed_stats'] is Map<String, dynamic>
          ? map['speed_stats'] as Map<String, dynamic>
          : null),
      distanceM: map['distance_m'] is num ? (map['distance_m'] as num).toDouble() : null,
      createdAtMs: map['created_at'] is int
          ? map['created_at'] as int
          : map['created_at'] is num
              ? (map['created_at'] as num).toInt()
              : null,
    );
  }
}

class SpeedStats {
  final double minMps;
  final double maxMps;
  final double avgMps;

  SpeedStats({
    required this.minMps,
    required this.maxMps,
    required this.avgMps,
  });
}
