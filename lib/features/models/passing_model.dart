import 'package:cloud_firestore/cloud_firestore.dart';

class PassingModel {
  final String id;
  final String raceId;
  final String? eventId;
  final String? sessionId;
  final String participantUid;
  final String driverName;
  final String carNumber; // Or color/identifier
  final DateTime timestamp;
  final int checkpointIndex; // 0 = Start/Finish, 1 = Sector 1, etc.
  final int lapNumber;
  final double?
      lapTime; // Milliseconds, populated if this passing completes a lap
  final double? sectorTime; // Milliseconds since last checkpoint
  final double? splitTime; // Milliseconds since lap start
  final double? trapSpeed; // m/s at checkpoint
  final bool? valid;
  final List<String>
      flags; // ['best_lap', 'personal_best', 'invalid', 'manual']

  PassingModel({
    required this.id,
    required this.raceId,
    this.eventId,
    this.sessionId,
    required this.participantUid,
    required this.driverName,
    required this.carNumber,
    required this.timestamp,
    required this.checkpointIndex,
    required this.lapNumber,
    this.lapTime,
    this.sectorTime,
    this.splitTime,
    this.trapSpeed,
    this.valid,
    this.flags = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'race_id': raceId,
      'event_id': eventId,
      'session_id': sessionId,
      'participant_uid': participantUid,
      'driver_name': driverName,
      'car_number': carNumber,
      'timestamp': Timestamp.fromDate(timestamp),
      'checkpoint_index': checkpointIndex,
      'lap_number': lapNumber,
      'lap_time': lapTime,
      'sector_time': sectorTime,
      'split_time': splitTime,
      'trap_speed': trapSpeed,
      'valid': valid,
      'flags': flags,
    };
  }

  factory PassingModel.fromMap(String id, Map<String, dynamic> map) {
    // Debug: print raw data to see what we're receiving

    return PassingModel(
      id: id,
      raceId: map['race_id'] ?? '',
      eventId: map['event_id'],
      sessionId: map['session_id'],
      participantUid: map['participant_uid'] ?? '',
      driverName: map['driver_name'] ?? 'Unknown',
      carNumber: map['car_number'] ?? '',
      timestamp: _parseTimestamp(map['timestamp']),
      checkpointIndex: map['checkpoint_index'] ?? 0,
      lapNumber: map['lap_number'] ?? 0,
      lapTime: (map['lap_time'] as num?)?.toDouble(),
      sectorTime: (map['sector_time'] as num?)?.toDouble(),
      splitTime: (map['split_time'] as num?)?.toDouble(),
      trapSpeed: (map['trap_speed'] as num?)?.toDouble(),
      valid: map['valid'] as bool?,
      flags: List<String>.from(map['flags'] ?? []),
    );
  }

  /// Helper to parse timestamp from either Firestore Timestamp or int milliseconds
  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();

    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      return DateTime.now();
    }
  }
}
