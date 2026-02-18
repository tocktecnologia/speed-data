class SessionAnalysisSummaryModel {
  final int? bestLapMs;
  final int? optimalLapMs;
  final List<int> bestSectorsMs;
  final int validLapsCount;
  final int totalLapsCount;
  final int? updatedAtMs;

  SessionAnalysisSummaryModel({
    this.bestLapMs,
    this.optimalLapMs,
    required this.bestSectorsMs,
    required this.validLapsCount,
    required this.totalLapsCount,
    this.updatedAtMs,
  });

  factory SessionAnalysisSummaryModel.fromMap(Map<String, dynamic> map) {
    List<int> _intList(dynamic v) {
      if (v is List) return v.whereType<num>().map((e) => e.toInt()).toList();
      return const [];
    }

    int? _int(dynamic v) => v is num ? v.toInt() : null;

    return SessionAnalysisSummaryModel(
      bestLapMs: _int(map['best_lap_ms']),
      optimalLapMs: _int(map['optimal_lap_ms']),
      bestSectorsMs: _intList(map['best_sectors_ms']),
      validLapsCount: _int(map['valid_laps_count']) ?? 0,
      totalLapsCount: _int(map['total_laps_count']) ?? 0,
      updatedAtMs: _int(map['updated_at']),
    );
  }
}
