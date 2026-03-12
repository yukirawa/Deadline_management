import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/user_settings.dart';
import 'package:kigenkanri/widgets/notification_preferences_form.dart';

void main() {
  testWidgets('NotificationPreferencesForm は曜日未選択の定時通知を保存させない', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              NotificationPreferencesForm(
                initialSettings: UserSettings.defaults(),
                onSave: (_) async {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('定時通知を追加'));
    await tester.pumpAndSettle();

    for (final label in const ['月', '火', '水', '木', '金', '土', '日']) {
      await tester.tap(find.widgetWithText(FilterChip, label));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, '通知設定を保存');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('定時通知の曜日を1つ以上選択してください'), findsOneWidget);
  });

  testWidgets('NotificationPreferencesForm は有効な通知設定を保存できる', (
    WidgetTester tester,
  ) async {
    UserSettings? savedSettings;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              NotificationPreferencesForm(
                initialSettings: UserSettings.defaults(),
                onSave: (settings) async {
                  savedSettings = settings;
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('定時通知を追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, '通知設定を保存');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedSettings, isNotNull);
    expect(savedSettings!.dailySummaryRules, hasLength(1));
    expect(savedSettings!.dailySummaryRules.first.time, '07:00');
  });
}
