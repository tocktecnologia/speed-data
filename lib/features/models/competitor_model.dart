import 'package:cloud_firestore/cloud_firestore.dart';

class Competitor {
  final String id;
  final String groupId;
  final String teamId;
  final String teamName;

  // Driver Details
  final String firstName;
  final String lastName;
  final String driverReg; // License/Reg number
  final String email;
  final String uid; // Linked User UID

  // Vehicle Details
  final String number; // Race Number (max 4 chars)
  final String category; // Category/Class
  final String vehicleReg; // Chassis/Car Reg
  final String label; // TLA (Three Letter Abbreviation) for scoreboards

  // Additional Data
  final Map<String, String> additionalFields; // Sponsor, City, Club, etc.
  final String paymentStatus; // pending | paid
  final DateTime? paymentConfirmedAt;
  final String paymentMethod; // manual_pix, cash, transfer, etc

  Competitor({
    required this.id,
    required this.groupId,
    this.teamId = '',
    this.teamName = '',
    required this.firstName,
    required this.lastName,
    required this.number,
    this.driverReg = '',
    this.email = '',
    this.uid = '',
    this.category = '',
    this.vehicleReg = '',
    this.label = '',
    this.additionalFields = const {},
    this.paymentStatus = 'pending',
    this.paymentConfirmedAt,
    this.paymentMethod = '',
  });

  Competitor copyWith({
    String? id,
    String? groupId,
    String? teamId,
    String? teamName,
    String? firstName,
    String? lastName,
    String? number,
    String? driverReg,
    String? email,
    String? uid,
    String? category,
    String? vehicleReg,
    String? label,
    Map<String, String>? additionalFields,
    String? paymentStatus,
    DateTime? paymentConfirmedAt,
    String? paymentMethod,
  }) {
    return Competitor(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      teamId: teamId ?? this.teamId,
      teamName: teamName ?? this.teamName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      number: number ?? this.number,
      driverReg: driverReg ?? this.driverReg,
      email: email ?? this.email,
      uid: uid ?? this.uid,
      category: category ?? this.category,
      vehicleReg: vehicleReg ?? this.vehicleReg,
      label: label ?? this.label,
      additionalFields: additionalFields ?? this.additionalFields,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentConfirmedAt: paymentConfirmedAt ?? this.paymentConfirmedAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }

  // Helper for display name
  String get name => '$firstName $lastName'.trim();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'team_id': teamId,
      'team_name': teamName,
      'first_name': firstName,
      'last_name': lastName,
      'driver_reg': driverReg,
      'email': email,
      'uid': uid,
      'number': number,
      'category': category,
      'vehicle_reg': vehicleReg,
      'label': label,
      'additional_fields': additionalFields,
      'payment_status':
          paymentStatus.trim().isEmpty ? 'pending' : paymentStatus,
      'payment_confirmed_at': paymentConfirmedAt != null
          ? Timestamp.fromDate(paymentConfirmedAt!)
          : null,
      'payment_method': paymentMethod,
    };
  }

  factory Competitor.fromMap(Map<String, dynamic> map) {
    final paymentConfirmedRaw = map['payment_confirmed_at'];
    DateTime? paymentConfirmedAt;
    if (paymentConfirmedRaw is Timestamp) {
      paymentConfirmedAt = paymentConfirmedRaw.toDate();
    } else if (paymentConfirmedRaw is DateTime) {
      paymentConfirmedAt = paymentConfirmedRaw;
    } else if (paymentConfirmedRaw is int) {
      paymentConfirmedAt =
          DateTime.fromMillisecondsSinceEpoch(paymentConfirmedRaw);
    }

    return Competitor(
      id: map['id'] ?? '',
      groupId: map['group_id'] ?? '',
      teamId: map['team_id'] ?? '',
      teamName: map['team_name'] ??
          ((map['additional_fields'] is Map)
              ? (Map<String, dynamic>.from(map['additional_fields'])['Team']
                      ?.toString() ??
                  '')
              : ''),
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      driverReg: map['driver_reg'] ?? '',
      email: map['email'] ?? '',
      uid: map['uid'] ?? '',
      number: map['number'] ?? '',
      category: map['category'] ?? '',
      vehicleReg: map['vehicle_reg'] ?? '',
      label: map['label'] ?? '',
      additionalFields:
          Map<String, String>.from(map['additional_fields'] ?? {}),
      paymentStatus:
          (map['payment_status'] as String?)?.trim().isNotEmpty == true
              ? (map['payment_status'] as String).trim().toLowerCase()
              : 'pending',
      paymentConfirmedAt: paymentConfirmedAt,
      paymentMethod: (map['payment_method'] as String?)?.trim() ?? '',
    );
  }
}
