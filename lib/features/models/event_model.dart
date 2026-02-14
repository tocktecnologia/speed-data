
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/race_group_model.dart';

class RaceEvent {
  final String id;
  final String name;
  final String trackId; // Reference to the 'races' (track) collection
  final String organizerId;
  final DateTime date;
  final DateTime? endDate; // Optional end date
  // drivers are now managed via sub-collection 'competitors' or similar pattern
  // keeping driverIds for backward compatibility or quick lookup if needed, but primary is Competitor model
  final List<String> driverIds; 
  final List<RaceSession> sessions;
  final List<RaceGroup> groups;

  RaceEvent({
    required this.id,
    required this.name,
    required this.trackId,
    required this.organizerId,
    required this.date,
    this.endDate,
    this.driverIds = const [],
    this.sessions = const [],
    this.groups = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'track_id': trackId,
      'organizer_id': organizerId,
      'date': Timestamp.fromDate(date),
      'end_date': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'driver_ids': driverIds,
      'sessions': sessions.map((s) => s.toMap()).toList(),
      'groups': groups.map((g) => g.toMap()).toList(),
    };
  }

  factory RaceEvent.fromMap(String id, Map<String, dynamic> map) {
    return RaceEvent(
      id: id,
      name: map['name'] is String ? map['name'] : '',
      trackId: map['track_id'] is String ? map['track_id'] : '',
      organizerId: map['organizer_id'] is String ? map['organizer_id'] : '',
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (map['end_date'] as Timestamp?)?.toDate(),
      driverIds: map['driver_ids'] is List ? List<String>.from(map['driver_ids']) : [],
      sessions: map['sessions'] is List 
          ? (map['sessions'] as List)
              .where((s) => s is Map<String, dynamic>)
              .map((s) => RaceSession.fromMap(s as Map<String, dynamic>))
              .toList() 
          : [],
      groups: map['groups'] is List
          ? (map['groups'] as List)
              .where((g) => g is Map<String, dynamic>)
              .map((g) => RaceGroup.fromMap(g as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  RaceEvent copyWith({
    String? id,
    String? name,
    String? trackId,
    String? organizerId,
    DateTime? date,
    DateTime? endDate,
    List<String>? driverIds,
    List<RaceSession>? sessions,
    List<RaceGroup>? groups,
  }) {
    return RaceEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      trackId: trackId ?? this.trackId,
      organizerId: organizerId ?? this.organizerId,
      date: date ?? this.date,
      endDate: endDate ?? this.endDate,
      driverIds: driverIds ?? this.driverIds,
      sessions: sessions ?? this.sessions,
      groups: groups ?? this.groups,
    );
  }
}
