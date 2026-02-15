enum SessionType { practice, qualifying, race }

enum SessionStatus { scheduled, active, finished }

enum RaceFlag { green, yellow, red, checkered }

class RaceSession {
  final String id;
  final SessionType type;
  final SessionStatus status;
  final RaceFlag currentFlag;
  final DateTime scheduledTime;
  final int durationMinutes; 
  final int? totalLaps; 
  final String groupId;
  final String name;
  final String shortName;
  
  // Timing Settings
  final String startMethod; // 'First Passing', 'Flag', 'Staggered'
  final bool startOnFirstPassing;
  final int minLapTimeSeconds;
  final bool redFlagStopsClock;
  final bool redFlagDeletesPassings;
  
  // Auto Finish Settings
  final String finishMode; // 'Laps', 'Time', 'TimeAndLaps', 'TimeOrLaps', 'Individual'
  
  // Qualification
  final String qualificationCriteria; // 'None', 'Max % Best Lap', etc.
  final double? qualificationValue; // e.g., 107%
  
  // Dynamic State (Orbits style)
  final DateTime? actualStartTime;
  final DateTime? actualEndTime;

  RaceSession({
    required this.id,
    required this.type,
    required this.status,
    this.currentFlag = RaceFlag.green,
    required this.scheduledTime,
    this.durationMinutes = 60,
    this.totalLaps,
    this.groupId = '',
    this.name = '',
    this.shortName = '',
    this.startMethod = 'First Passing',
    this.startOnFirstPassing = true,
    this.minLapTimeSeconds = 0,
    this.redFlagStopsClock = true,
    this.redFlagDeletesPassings = false,
    this.finishMode = 'Time',
    this.qualificationCriteria = 'None',
    this.qualificationValue,
    this.actualStartTime,
    this.actualEndTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'status': status.name,
      'current_flag': currentFlag.name,
      'scheduled_time': scheduledTime.millisecondsSinceEpoch,
      'duration_minutes': durationMinutes,
      'total_laps': totalLaps,
      'group_id': groupId,
      'name': name,
      'short_name': shortName,
      'start_method': startMethod,
      'start_on_first_passing': startOnFirstPassing,
      'min_lap_time_seconds': minLapTimeSeconds,
      'red_flag_stops_clock': redFlagStopsClock,
      'red_flag_deletes_passings': redFlagDeletesPassings,
      'finish_mode': finishMode,
      'qualification_criteria': qualificationCriteria,
      'qualification_value': qualificationValue,
      'actual_start_time': actualStartTime?.millisecondsSinceEpoch,
      'actual_end_time': actualEndTime?.millisecondsSinceEpoch,
    };
  }

  factory RaceSession.fromMap(Map<String, dynamic> map) {
    return RaceSession(
      id: map['id'] is String ? map['id'] : '',
      type: SessionType.values.firstWhere(
          (e) => e.name == map['type'], orElse: () => SessionType.practice),
      status: SessionStatus.values.firstWhere(
          (e) => e.name == map['status'], orElse: () => SessionStatus.scheduled),
      currentFlag: RaceFlag.values.firstWhere(
          (e) => e.name == (map['current_flag'] ?? map['flag']), orElse: () => RaceFlag.green),
      scheduledTime: DateTime.fromMillisecondsSinceEpoch(
          map['scheduled_time'] is num ? (map['scheduled_time'] as num).toInt() : 0),
      durationMinutes: map['duration_minutes'] is num ? (map['duration_minutes'] as num).toInt() : 60,
      totalLaps: map['total_laps'] is num ? (map['total_laps'] as num).toInt() : null,
      groupId: map['group_id'] is String ? map['group_id'] : '',
      name: map['name'] is String ? map['name'] : '',
      shortName: map['short_name'] is String ? map['short_name'] : '',
      startMethod: map['start_method'] is String ? map['start_method'] : 'First Passing',
      startOnFirstPassing: map['start_on_first_passing'] is bool ? map['start_on_first_passing'] : true,
      minLapTimeSeconds: map['min_lap_time_seconds'] is num ? (map['min_lap_time_seconds'] as num).toInt() : 0,
      redFlagStopsClock: map['red_flag_stops_clock'] is bool ? map['red_flag_stops_clock'] : true,
      redFlagDeletesPassings: map['red_flag_deletes_passings'] is bool ? map['red_flag_deletes_passings'] : false,
      finishMode: map['finish_mode'] is String ? map['finish_mode'] : 'Time',
      qualificationCriteria: map['qualification_criteria'] as String? ?? 'None',
      qualificationValue: map['qualification_value'] is num ? (map['qualification_value'] as num).toDouble() : null,
      actualStartTime: map['actual_start_time'] != null ? DateTime.fromMillisecondsSinceEpoch(map['actual_start_time']) : null,
      actualEndTime: map['actual_end_time'] != null ? DateTime.fromMillisecondsSinceEpoch(map['actual_end_time']) : null,
    );
  }

  RaceSession copyWith({
    String? id,
    SessionType? type,
    SessionStatus? status,
    RaceFlag? currentFlag,
    DateTime? scheduledTime,
    int? durationMinutes,
    int? totalLaps,
    String? groupId,
    String? name,
    String? shortName,
    String? startMethod,
    bool? startOnFirstPassing,
    int? minLapTimeSeconds,
    bool? redFlagStopsClock,
    bool? redFlagDeletesPassings,
    String? finishMode,
    String? qualificationCriteria,
    double? qualificationValue,
    DateTime? actualStartTime,
    DateTime? actualEndTime,
  }) {
    return RaceSession(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      currentFlag: currentFlag ?? this.currentFlag,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      totalLaps: totalLaps ?? this.totalLaps,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      startMethod: startMethod ?? this.startMethod,
      startOnFirstPassing: startOnFirstPassing ?? this.startOnFirstPassing,
      minLapTimeSeconds: minLapTimeSeconds ?? this.minLapTimeSeconds,
      redFlagStopsClock: redFlagStopsClock ?? this.redFlagStopsClock,
      redFlagDeletesPassings: redFlagDeletesPassings ?? this.redFlagDeletesPassings,
      finishMode: finishMode ?? this.finishMode,
      qualificationCriteria: qualificationCriteria ?? this.qualificationCriteria,
      qualificationValue: qualificationValue ?? this.qualificationValue,
      actualStartTime: actualStartTime ?? this.actualStartTime,
      actualEndTime: actualEndTime ?? this.actualEndTime,
    );
  }
}
