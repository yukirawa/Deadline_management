class UserSettings {
  const UserSettings({
    required this.notificationsEnabled,
    required this.timezone,
    required this.migratedLocalV1,
    required this.updatedAt,
  });

  static const String defaultTimezone = 'Asia/Tokyo';

  final bool notificationsEnabled;
  final String timezone;
  final bool migratedLocalV1;
  final int updatedAt;

  factory UserSettings.defaults() {
    return UserSettings(
      notificationsEnabled: false,
      timezone: defaultTimezone,
      migratedLocalV1: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  UserSettings copyWith({
    bool? notificationsEnabled,
    String? timezone,
    bool? migratedLocalV1,
    int? updatedAt,
  }) {
    return UserSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      timezone: timezone ?? this.timezone,
      migratedLocalV1: migratedLocalV1 ?? this.migratedLocalV1,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notificationsEnabled': notificationsEnabled,
      'timezone': timezone,
      'migratedLocalV1': migratedLocalV1,
      'updatedAt': updatedAt,
    };
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      notificationsEnabled: (json['notificationsEnabled'] as bool?) ?? false,
      timezone: (json['timezone'] as String?) ?? defaultTimezone,
      migratedLocalV1: (json['migratedLocalV1'] as bool?) ?? false,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
