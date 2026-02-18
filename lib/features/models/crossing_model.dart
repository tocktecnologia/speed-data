class CrossingModel {
  final String id;
  final int lapNumber;
  final int checkpointIndex;
  final int crossedAtMs;
  final double speedMps;
  final double lat;
  final double lng;
  final int? sectorTimeMs;
  final int? splitTimeMs;
  final String method;
  final double distanceToCheckpointM;
  final double confidence;
  final int? createdAtMs;

  CrossingModel({
    required this.id,
    required this.lapNumber,
    required this.checkpointIndex,
    required this.crossedAtMs,
    required this.speedMps,
    required this.lat,
    required this.lng,
    required this.method,
    required this.distanceToCheckpointM,
    required this.confidence,
    this.sectorTimeMs,
    this.splitTimeMs,
    this.createdAtMs,
  });

  factory CrossingModel.fromMap(String id, Map<String, dynamic> map) {
    num _num(dynamic v, num fallback) => v is num ? v : fallback;

    return CrossingModel(
      id: id,
      lapNumber: map['lap_number'] is num ? (map['lap_number'] as num).toInt() : 0,
      checkpointIndex:
          map['checkpoint_index'] is num ? (map['checkpoint_index'] as num).toInt() : 0,
      crossedAtMs: map['crossed_at_ms'] is num ? (map['crossed_at_ms'] as num).toInt() : 0,
      speedMps: _num(map['speed_mps'], 0).toDouble(),
      lat: _num(map['lat'], 0).toDouble(),
      lng: _num(map['lng'], 0).toDouble(),
      sectorTimeMs: map['sector_time_ms'] is num ? (map['sector_time_ms'] as num).toInt() : null,
      splitTimeMs: map['split_time_ms'] is num ? (map['split_time_ms'] as num).toInt() : null,
      method: (map['method'] ?? 'unknown').toString(),
      distanceToCheckpointM:
          _num(map['distance_to_checkpoint_m'], 0).toDouble(),
      confidence: _num(map['confidence'], 0).toDouble(),
      createdAtMs: map['created_at'] is int
          ? map['created_at'] as int
          : map['created_at'] is num
              ? (map['created_at'] as num).toInt()
              : null,
    );
  }
}
