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
    return PassingModel(
      id: id,
      raceId: _parseString(map['race_id']) ?? '',
      eventId: _parseString(map['event_id']),
      sessionId: _parseString(map['session_id']),
      participantUid: _parseString(map['participant_uid']) ??
          _parseString(map['uid']) ??
          '',
      driverName: _parseString(map['driver_name']) ??
          _parseString(map['display_name']) ??
          'Unknown',
      carNumber:
          _parseString(map['car_number']) ?? _parseString(map['number']) ?? '',
      timestamp: _parseTimestamp(map['timestamp']),
      checkpointIndex: _parseInt(map['checkpoint_index']) ??
          _parseInt(map['checkpoint']) ??
          0,
      lapNumber: _parseInt(map['lap_number']) ?? _parseInt(map['lap']) ?? 0,
      lapTime: _parseDouble(map['lap_time']) ??
          _parseDouble(map['lap_time_ms']) ??
          _parseDouble(map['total_lap_time_ms']),
      sectorTime: _parseDouble(map['sector_time']) ??
          _parseDouble(map['sector_time_ms']),
      splitTime:
          _parseDouble(map['split_time']) ?? _parseDouble(map['split_time_ms']),
      trapSpeed: _parseDouble(map['trap_speed']) ??
          _parseDouble(map['trap_speed_mps']) ??
          _parseDouble(map['speed_mps']),
      valid: map['valid'] as bool?,
      flags: (map['flags'] is List)
          ? List<String>.from((map['flags'] as List)
              .where((value) => value != null)
              .map((value) => value.toString()))
          : const [],
    );
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final parsed = value.toString().trim();
    return parsed.isEmpty ? null : parsed;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// Helper to parse timestamp from either Firestore Timestamp or int milliseconds
  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();

    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is DateTime) {
      return timestamp;
    } else if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is num) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
    } else if (timestamp is String) {
      final parsedIso = DateTime.tryParse(timestamp);
      if (parsedIso != null) return parsedIso;
      final parsedMs = int.tryParse(timestamp);
      if (parsedMs != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsedMs);
      }
      return DateTime.now();
    } else {
      return DateTime.now();
    }
  }
}
