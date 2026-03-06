import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/screens/add_task_page.dart';
import 'package:kigenkanri/screens/firebase_setup_page.dart';

void main() {
  testWidgets('TaskFormPageは未入力のまま保存できない', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TaskFormPage()));

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('科目を入力してください'), findsOneWidget);
    expect(find.text('内容を入力してください'), findsOneWidget);
    expect(find.text('締切日を選択してください'), findsOneWidget);
  });

  testWidgets('FirebaseSetupPageが不足メッセージを表示する', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FirebaseSetupPage(message: 'sample setup error')),
    );

    expect(find.text('Firebase設定が必要です'), findsOneWidget);
    expect(find.textContaining('sample setup error'), findsOneWidget);
  });
}
