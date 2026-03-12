import 'package:flutter/foundation.dart';
import 'package:kigenkanri/models/notification_rules.dart';

class UserSettings {
  const UserSettings({
    required this.notificationsEnabled,
    required this.timezone,
    required this.migratedLocalV1,
    required this.deadlineReminderRules,
    required this.dailySummaryRules,
    required this.updatedAt,
  });

  static const String defaultTimezone = 'Asia/Tokyo';

  final bool notificationsEnabled;
  final String timezone;
  final bool migratedLocalV1;
  final List<DeadlineReminderRule> deadlineReminderRules;
  final List<DailySummaryRule> dailySummaryRules;
  final int updatedAt;

  factory UserSettings.defaults() {
    return UserSettings(
      notificationsEnabled: false,
      timezone: defaultTimezone,
      migratedLocalV1: false,
      deadlineReminderRules: defaultDeadlineReminderRules(),
      dailySummaryRules: defaultDailySummaryRules(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  UserSettings copyWith({
    bool? notificationsEnabled,
    String? timezone,
    bool? migratedLocalV1,
    List<DeadlineReminderRule>? deadlineReminderRules,
    List<DailySummaryRule>? dailySummaryRules,
    int? updatedAt,
  }) {
    return UserSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      timezone: timezone ?? this.timezone,
      migratedLocalV1: migratedLocalV1 ?? this.migratedLocalV1,
      deadlineReminderRules:
          deadlineReminderRules ?? this.deadlineReminderRules,
      dailySummaryRules: dailySummaryRules ?? this.dailySummaryRules,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notificationsEnabled': notificationsEnabled,
      'timezone': timezone,
      'migratedLocalV1': migratedLocalV1,
      'deadlineReminderRules': deadlineReminderRules
          .map((rule) => rule.toJson())
          .toList(),
      'dailySummaryRules': dailySummaryRules
          .map((rule) => rule.toJson())
          .toList(),
      'updatedAt': updatedAt,
    };
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    final rawDeadlineRules = json['deadlineReminderRules'];
    final rawDailySummaryRules = json['dailySummaryRules'];

    return UserSettings(
      notificationsEnabled: (json['notificationsEnabled'] as bool?) ?? false,
      timezone: (json['timezone'] as String?) ?? defaultTimezone,
      migratedLocalV1: (json['migratedLocalV1'] as bool?) ?? false,
      deadlineReminderRules: rawDeadlineRules is List
          ? rawDeadlineRules
                .whereType<Map>()
                .map(
                  (item) => DeadlineReminderRule.fromJson(
                    item.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : defaultDeadlineReminderRules(),
      dailySummaryRules: rawDailySummaryRules is List
          ? rawDailySummaryRules
                .whereType<Map>()
                .map(
                  (item) => DailySummaryRule.fromJson(
                    item.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : defaultDailySummaryRules(),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UserSettings &&
        other.notificationsEnabled == notificationsEnabled &&
        other.timezone == timezone &&
        other.migratedLocalV1 == migratedLocalV1 &&
        listEquals(other.deadlineReminderRules, deadlineReminderRules) &&
        listEquals(other.dailySummaryRules, dailySummaryRules) &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    notificationsEnabled,
    timezone,
    migratedLocalV1,
    Object.hashAll(deadlineReminderRules),
    Object.hashAll(dailySummaryRules),
    updatedAt,
  );
}
