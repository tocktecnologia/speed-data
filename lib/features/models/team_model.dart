import 'package:cloud_firestore/cloud_firestore.dart';

class TeamModel {
  final String id;
  final String name;
  final String normalizedName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TeamModel({
    required this.id,
    required this.name,
    this.normalizedName = '',
    this.createdAt,
    this.updatedAt,
  });

  TeamModel copyWith({
    String? id,
    String? name,
    String? normalizedName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamModel(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'normalized_name': normalizedName.isNotEmpty
          ? normalizedName
          : name.trim().toLowerCase(),
      'created_at': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  factory TeamModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? asDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num)
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      return null;
    }

    final name = (map['name'] as String?)?.trim() ?? '';
    return TeamModel(
      id: id,
      name: name,
      normalizedName:
          (map['normalized_name'] as String?)?.trim().toLowerCase() ??
              name.toLowerCase(),
      createdAt: asDate(map['created_at']),
      updatedAt: asDate(map['updated_at']),
    );
  }
}

class TeamMember {
  final String uid;
  final String role; // staff | pilot
  final String name;
  final String email;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TeamMember({
    required this.uid,
    this.role = 'staff',
    this.name = '',
    this.email = '',
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  TeamMember copyWith({
    String? uid,
    String? role,
    String? name,
    String? email,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamMember(
      uid: uid ?? this.uid,
      role: role ?? this.role,
      name: name ?? this.name,
      email: email ?? this.email,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap(
      {required String eventId, required String teamId}) {
    return {
      'uid': uid,
      'role': role,
      'name': name,
      'email': email.trim().toLowerCase(),
      'active': active,
      'event_id': eventId,
      'team_id': teamId,
      'created_at': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  factory TeamMember.fromMap(Map<String, dynamic> map) {
    DateTime? asDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num)
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      return null;
    }

    return TeamMember(
      uid: (map['uid'] as String?)?.trim() ?? '',
      role: (map['role'] as String?)?.trim().toLowerCase() ?? 'staff',
      name: (map['name'] as String?)?.trim() ?? '',
      email: (map['email'] as String?)?.trim().toLowerCase() ?? '',
      active: map['active'] is bool ? map['active'] : true,
      createdAt: asDate(map['created_at']),
      updatedAt: asDate(map['updated_at']),
    );
  }
}

class TeamMembership {
  final String eventId;
  final String teamId;
  final String uid;
  final String role;
  final String name;
  final String email;

  const TeamMembership({
    required this.eventId,
    required this.teamId,
    required this.uid,
    required this.role,
    required this.name,
    required this.email,
  });
}
