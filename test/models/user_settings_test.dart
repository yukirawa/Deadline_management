import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/user_settings.dart';

void main() {
  test('UserSettings は通知ルールを含めて JSON 往復できる', () {
    final settings = UserSettings.defaults().copyWith(
      notificationsEnabled: true,
      timezone: 'America/New_York',
      updatedAt: 123,
    );

    final restored = UserSettings.fromJson(settings.toJson());

    expect(restored.notificationsEnabled, isTrue);
    expect(restored.timezone, 'America/New_York');
    expect(restored.deadlineReminderRules, settings.deadlineReminderRules);
    expect(restored.dailySummaryRules, settings.dailySummaryRules);
  });

  test('UserSettings は通知ルール欠損時に既定値を補う', () {
    final restored = UserSettings.fromJson(const {
      'notificationsEnabled': false,
      'timezone': 'Asia/Tokyo',
      'migratedLocalV1': true,
      'updatedAt': 10,
    });

    expect(restored.deadlineReminderRules.length, 2);
    expect(restored.dailySummaryRules, isEmpty);
  });
}
