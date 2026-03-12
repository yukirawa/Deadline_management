import 'package:flutter/foundation.dart';

const int maxNotificationRulesPerType = 5;
const List<int> allWeekdays = [1, 2, 3, 4, 5, 6, 7];

class DeadlineReminderRule {
  const DeadlineReminderRule({
    required this.id,
    required this.offsetMinutes,
    required this.enabled,
  });

  final String id;
  final int offsetMinutes;
  final bool enabled;

  DeadlineReminderRule copyWith({
    String? id,
    int? offsetMinutes,
    bool? enabled,
  }) {
    return DeadlineReminderRule(
      id: id ?? this.id,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'offsetMinutes': offsetMinutes, 'enabled': enabled};
  }

  factory DeadlineReminderRule.fromJson(Map<String, dynamic> json) {
    return DeadlineReminderRule(
      id: (json['id'] as String?) ?? '',
      offsetMinutes: (json['offsetMinutes'] as num?)?.toInt() ?? 0,
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DeadlineReminderRule &&
        other.id == id &&
        other.offsetMinutes == offsetMinutes &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(id, offsetMinutes, enabled);
}

class DailySummaryRule {
  const DailySummaryRule({
    required this.id,
    required this.time,
    required this.weekdays,
    required this.enabled,
  });

  final String id;
  final String time;
  final List<int> weekdays;
  final bool enabled;

  DailySummaryRule copyWith({
    String? id,
    String? time,
    List<int>? weekdays,
    bool? enabled,
  }) {
    return DailySummaryRule(
      id: id ?? this.id,
      time: time ?? this.time,
      weekdays: weekdays ?? this.weekdays,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'time': time, 'weekdays': weekdays, 'enabled': enabled};
  }

  factory DailySummaryRule.fromJson(Map<String, dynamic> json) {
    final weekdays =
        (json['weekdays'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => (value as num?)?.toInt())
            .whereType<int>()
            .where((value) => value >= 1 && value <= 7)
            .toSet()
            .toList()
          ..sort();

    return DailySummaryRule(
      id: (json['id'] as String?) ?? '',
      time: (json['time'] as String?) ?? '00:00',
      weekdays: weekdays,
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DailySummaryRule &&
        other.id == id &&
        other.time == time &&
        listEquals(other.weekdays, weekdays) &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(id, time, Object.hashAll(weekdays), enabled);
}

List<DeadlineReminderRule> defaultDeadlineReminderRules() {
  return const [
    DeadlineReminderRule(
      id: 'deadline-24h',
      offsetMinutes: 24 * 60,
      enabled: true,
    ),
    DeadlineReminderRule(
      id: 'deadline-2h',
      offsetMinutes: 2 * 60,
      enabled: true,
    ),
  ];
}

List<DailySummaryRule> defaultDailySummaryRules() {
  return const [];
}

bool isValidQuarterHourValue(int value) {
  return value >= 0 && value % 15 == 0;
}

bool isValidQuarterHourTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return false;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return false;
  }
  return hour >= 0 &&
      hour <= 23 &&
      minute >= 0 &&
      minute <= 59 &&
      minute % 15 == 0;
}

String formatOffsetLabel(int offsetMinutes) {
  final days = offsetMinutes ~/ (24 * 60);
  final remainingAfterDays = offsetMinutes % (24 * 60);
  final hours = remainingAfterDays ~/ 60;
  final minutes = remainingAfterDays % 60;
  final segments = <String>[];

  if (days > 0) {
    segments.add('$days日');
  }
  if (hours > 0) {
    segments.add('$hours時間');
  }
  if (minutes > 0) {
    segments.add('$minutes分');
  }
  if (segments.isEmpty) {
    return '期限ちょうど';
  }
  return '${segments.join(' ')}前';
}

String weekdayLabel(int weekday) {
  switch (weekday) {
    case 1:
      return '月';
    case 2:
      return '火';
    case 3:
      return '水';
    case 4:
      return '木';
    case 5:
      return '金';
    case 6:
      return '土';
    case 7:
      return '日';
    default:
      return '?';
  }
}

String formatWeekdaySummary(List<int> weekdays) {
  final normalized = weekdays.toSet().toList()..sort();
  if (listEquals(normalized, allWeekdays)) {
    return '毎日';
  }
  return normalized.map(weekdayLabel).join(' ');
}

String? validateDeadlineReminderRules(List<DeadlineReminderRule> rules) {
  if (rules.length > maxNotificationRulesPerType) {
    return '期限前通知は最大5件までです';
  }

  final offsets = <int>{};
  for (final rule in rules) {
    if (rule.id.isEmpty) {
      return '期限前通知のIDが不正です';
    }
    if (!isValidQuarterHourValue(rule.offsetMinutes)) {
      return '期限前通知は15分単位で設定してください';
    }
    if (!offsets.add(rule.offsetMinutes)) {
      return '同じ期限前通知は重複して設定できません';
    }
  }
  return null;
}

String? validateDailySummaryRules(List<DailySummaryRule> rules) {
  if (rules.length > maxNotificationRulesPerType) {
    return '定時通知は最大5件までです';
  }

  final times = <String>{};
  for (final rule in rules) {
    if (rule.id.isEmpty) {
      return '定時通知のIDが不正です';
    }
    if (!isValidQuarterHourTime(rule.time)) {
      return '定時通知の時刻は15分単位で設定してください';
    }
    if (rule.weekdays.isEmpty) {
      return '定時通知の曜日を1つ以上選択してください';
    }
    if (rule.weekdays.any((weekday) => weekday < 1 || weekday > 7)) {
      return '定時通知の曜日が不正です';
    }
    if (!times.add(rule.time)) {
      return '同じ時刻の定時通知は重複して設定できません';
    }
  }
  return null;
}
