import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/notification_rules.dart';

void main() {
  test('期限前通知はオフセット重複を許可しない', () {
    final error = validateDeadlineReminderRules([
      const DeadlineReminderRule(
        id: 'deadline-1',
        offsetMinutes: 120,
        enabled: true,
      ),
      const DeadlineReminderRule(
        id: 'deadline-2',
        offsetMinutes: 120,
        enabled: false,
      ),
    ]);

    expect(error, isNotNull);
  });

  test('定時通知は曜日未選択を許可しない', () {
    final error = validateDailySummaryRules([
      const DailySummaryRule(
        id: 'daily-1',
        time: '07:00',
        weekdays: [],
        enabled: true,
      ),
    ]);

    expect(error, isNotNull);
  });

  test('定時通知は最大5件まで', () {
    final rules = List.generate(
      6,
      (index) => DailySummaryRule(
        id: 'daily-$index',
        time: '${index.toString().padLeft(2, '0')}:00',
        weekdays: const [1, 2, 3, 4, 5],
        enabled: true,
      ),
    );

    final error = validateDailySummaryRules(rules);

    expect(error, isNotNull);
  });
}
