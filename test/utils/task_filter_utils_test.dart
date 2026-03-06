import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/utils/task_filter_utils.dart';

Task buildTask({
  required String id,
  required String subject,
  required String type,
  required String title,
  required bool done,
}) {
  return Task(
    id: id,
    subject: subject,
    type: type,
    title: title,
    dueDate: '2026-03-10',
    done: done,
    createdAt: 1,
    updatedAt: 1,
    isDeleted: false,
    deletedAt: null,
  );
}

void main() {
  final tasks = [
    buildTask(
      id: '1',
      subject: '数学',
      type: 'assignment',
      title: 'ワーク',
      done: false,
    ),
    buildTask(id: '2', subject: '英語', type: 'quiz', title: '単語テスト', done: true),
    buildTask(id: '3', subject: '理科', type: 'exam', title: '小テスト', done: false),
  ];

  test('検索語で科目・内容の部分一致フィルタが動作する', () {
    final result = filterTasks(
      tasks: tasks,
      query: 'ワーク',
      type: null,
      doneFilter: TaskDoneFilter.all,
    );
    expect(result.map((task) => task.id), ['1']);
  });

  test('種別と完了状態でフィルタできる', () {
    final result = filterTasks(
      tasks: tasks,
      query: '',
      type: 'quiz',
      doneFilter: TaskDoneFilter.done,
    );
    expect(result.map((task) => task.id), ['2']);
  });
}
