import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/screens/add_task_page.dart';
import 'package:kigenkanri/screens/firebase_setup_page.dart';

void main() {
  testWidgets('TaskFormPage は未入力のまま保存できない', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TaskFormPage()));

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('科目を入力してください'), findsOneWidget);
    expect(find.text('内容を入力してください'), findsOneWidget);
    expect(find.text('締切日を選択してください'), findsOneWidget);
  });

  testWidgets('TaskFormPage は締切時刻を設定できる', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskFormPage(
          initialTask: Task(
            id: 'task-1',
            subject: '数学',
            type: 'assignment',
            title: '課題',
            dueDate: '2026-03-10',
            dueTime: null,
            done: false,
            createdAt: 1,
            updatedAt: 1,
            isDeleted: false,
            deletedAt: null,
          ),
        ),
      ),
    );

    await tester.tap(find.text('時刻を設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('23:00'), findsOneWidget);
  });

  testWidgets('FirebaseSetupPage が不足メッセージを表示する', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FirebaseSetupPage(message: 'sample setup error')),
    );

    expect(find.textContaining('sample setup error'), findsOneWidget);
  });
}
