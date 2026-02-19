enum SessionType { practice, qualifying, race }

enum SessionStatus { scheduled, active, finished }

enum RaceFlag { green, warmup, yellow, red, checkered }

enum SessionTimelineType { startFinish, split, trap }

class SessionTimeline {
  final String id;
  final SessionTimelineType type;
  final String name;
  final int order;
  final int checkpointIndex;
  final bool enabled;

  const SessionTimeline({
    required this.id,
    required this.type,
    required this.name,
    required this.order,
    required this.checkpointIndex,
    this.enabled = true,
  });

  static SessionTimelineType parseType(dynamic value) {
    final normalized =
        value == null ? '' : value.toString().trim().toLowerCase();
    if (normalized == 'start_finish' ||
        normalized == 'startfinish' ||
        normalized == 'start-finish' ||
        normalized == 'sf') {
      return SessionTimelineType.startFinish;
    }
    if (normalized == 'trap') {
      return SessionTimelineType.trap;
    }
    return SessionTimelineType.split;
  }

  static String typeToStorage(SessionTimelineType type) {
    switch (type) {
      case SessionTimelineType.startFinish:
        return 'start_finish';
      case SessionTimelineType.split:
        return 'split';
      case SessionTimelineType.trap:
        return 'trap';
    }
  }

  factory SessionTimeline.fromMap(
    Map<String, dynamic> map, {
    int fallbackOrder = 0,
  }) {
    final timelineIdRaw = map['id'];
    final timelineId =
        timelineIdRaw is String && timelineIdRaw.trim().isNotEmpty
            ? timelineIdRaw.trim()
            : 'timeline_$fallbackOrder';

    final orderRaw = map['order'];
    final parsedOrder = orderRaw is num
        ? orderRaw.toInt()
        : int.tryParse('$orderRaw') ?? fallbackOrder;

    final checkpointRaw = map['checkpoint_index'] ?? map['checkpoint'];
    final parsedCheckpoint = checkpointRaw is num
        ? checkpointRaw.toInt()
        : int.tryParse('$checkpointRaw') ?? 0;

    return SessionTimeline(
      id: timelineId,
      type: parseType(map['type']),
      name: map['name'] is String ? map['name'].trim() : '',
      order: parsedOrder,
      checkpointIndex: parsedCheckpoint,
      enabled: map['enabled'] is bool ? map['enabled'] : true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': typeToStorage(type),
      'name': name,
      'order': order,
      'checkpoint_index': checkpointIndex,
      'enabled': enabled,
    };
  }

  SessionTimeline copyWith({
    String? id,
    SessionTimelineType? type,
    String? name,
    int? order,
    int? checkpointIndex,
    bool? enabled,
  }) {
    return SessionTimeline(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      order: order ?? this.order,
      checkpointIndex: checkpointIndex ?? this.checkpointIndex,
      enabled: enabled ?? this.enabled,
    );
  }
}

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
  final String
      finishMode; // 'Laps', 'Time', 'TimeAndLaps', 'TimeOrLaps', 'Individual'

  // Qualification
  final String qualificationCriteria; // 'None', 'Max % Best Lap', etc.
  final double? qualificationValue; // e.g., 107%

  // Dynamic State (Orbits style)
  final DateTime? actualStartTime;
  final DateTime? actualEndTime;
  final List<SessionTimeline> timelines;

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
    this.timelines = const [],
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
      'timelines': timelines.map((timeline) => timeline.toMap()).toList(),
    };
  }

  factory RaceSession.fromMap(Map<String, dynamic> map) {
    String _norm(dynamic value) =>
        value == null ? '' : value.toString().trim().toLowerCase();

    SessionType _parseType(dynamic value) {
      final v = _norm(value);
      if (v == 'qualifying' || v == 'qualification') {
        return SessionType.qualifying;
      }
      if (v == 'race' || v == 'corrida') {
        return SessionType.race;
      }
      return SessionType.practice;
    }

    SessionStatus _parseStatus(dynamic value) {
      final v = _norm(value);
      if (v == 'active' ||
          v == 'started' ||
          v == 'running' ||
          v == 'ativa' ||
          v == 'iniciada' ||
          v == 'em_andamento') {
        return SessionStatus.active;
      }
      if (v == 'finished' ||
          v == 'ended' ||
          v == 'closed' ||
          v == 'finalizada' ||
          v == 'encerrada' ||
          v == 'terminada') {
        return SessionStatus.finished;
      }
      return SessionStatus.scheduled;
    }

    RaceFlag _parseFlag(dynamic value) {
      final v = _norm(value);
      if (v == 'yellow') return RaceFlag.yellow;
      if (v == 'red') return RaceFlag.red;
      if (v == 'checkered' || v == 'chequered') return RaceFlag.checkered;
      if (v == 'warmup' || v == 'warm_up') return RaceFlag.warmup;
      return RaceFlag.green;
    }

    DateTime? _parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num)
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      if (value is String) {
        final parsedInt = int.tryParse(value);
        if (parsedInt != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsedInt);
        }
        return DateTime.tryParse(value);
      }
      try {
        // Timestamp from cloud_firestore
        final dynamic any = value;
        final date = any.toDate();
        if (date is DateTime) return date;
      } catch (_) {}
      return null;
    }

    List<SessionTimeline> _parseTimelines(dynamic value) {
      if (value is! List) return const [];
      final parsed = <SessionTimeline>[];
      for (int i = 0; i < value.length; i++) {
        final item = value[i];
        if (item is Map<String, dynamic>) {
          parsed.add(SessionTimeline.fromMap(item, fallbackOrder: i));
        } else if (item is Map) {
          parsed.add(SessionTimeline.fromMap(
            Map<String, dynamic>.from(item),
            fallbackOrder: i,
          ));
        }
      }
      parsed.sort((a, b) => a.order.compareTo(b.order));
      return parsed;
    }

    return RaceSession(
      id: map['id'] is String ? map['id'] : '',
      type: _parseType(map['type']),
      status: _parseStatus(map['status']),
      currentFlag: _parseFlag(map['current_flag'] ?? map['flag']),
      scheduledTime: DateTime.fromMillisecondsSinceEpoch(
          map['scheduled_time'] is num
              ? (map['scheduled_time'] as num).toInt()
              : 0),
      durationMinutes: map['duration_minutes'] is num
          ? (map['duration_minutes'] as num).toInt()
          : 60,
      totalLaps:
          map['total_laps'] is num ? (map['total_laps'] as num).toInt() : null,
      groupId: map['group_id'] is String ? map['group_id'] : '',
      name: map['name'] is String ? map['name'] : '',
      shortName: map['short_name'] is String ? map['short_name'] : '',
      startMethod:
          map['start_method'] is String ? map['start_method'] : 'First Passing',
      startOnFirstPassing: map['start_on_first_passing'] is bool
          ? map['start_on_first_passing']
          : true,
      minLapTimeSeconds: map['min_lap_time_seconds'] is num
          ? (map['min_lap_time_seconds'] as num).toInt()
          : 0,
      redFlagStopsClock: map['red_flag_stops_clock'] is bool
          ? map['red_flag_stops_clock']
          : true,
      redFlagDeletesPassings: map['red_flag_deletes_passings'] is bool
          ? map['red_flag_deletes_passings']
          : false,
      finishMode: map['finish_mode'] is String ? map['finish_mode'] : 'Time',
      qualificationCriteria: map['qualification_criteria'] as String? ?? 'None',
      qualificationValue: map['qualification_value'] is num
          ? (map['qualification_value'] as num).toDouble()
          : null,
      actualStartTime: _parseDate(map['actual_start_time']),
      actualEndTime: _parseDate(map['actual_end_time']),
      timelines: _parseTimelines(map['timelines'] ?? map['loops']),
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
    List<SessionTimeline>? timelines,
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
      redFlagDeletesPassings:
          redFlagDeletesPassings ?? this.redFlagDeletesPassings,
      finishMode: finishMode ?? this.finishMode,
      qualificationCriteria:
          qualificationCriteria ?? this.qualificationCriteria,
      qualificationValue: qualificationValue ?? this.qualificationValue,
      actualStartTime: actualStartTime ?? this.actualStartTime,
      actualEndTime: actualEndTime ?? this.actualEndTime,
      timelines: timelines ?? this.timelines,
    );
  }
}
