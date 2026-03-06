import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/utils/task_sync_utils.dart';

Task buildTask({
  required String id,
  required int updatedAt,
  required int createdAt,
  bool done = false,
  bool isDeleted = false,
  int? deletedAt,
  String dueDate = '2026-03-10',
}) {
  return Task(
    id: id,
    subject: '数学',
    type: 'assignment',
    title: '課題',
    dueDate: dueDate,
    done: done,
    createdAt: createdAt,
    updatedAt: updatedAt,
    isDeleted: isDeleted,
    deletedAt: deletedAt,
  );
}

void main() {
  test('LWWはupdatedAtが新しいタスクを採用する', () {
    final current = buildTask(id: 'a', updatedAt: 100, createdAt: 10);
    final incoming = buildTask(id: 'a', updatedAt: 200, createdAt: 9);

    final resolved = resolveByLww(current, incoming);

    expect(resolved.updatedAt, 200);
  });

  test('updatedAtが同一ならcreatedAtが大きい方を採用する', () {
    final current = buildTask(id: 'a', updatedAt: 100, createdAt: 10);
    final incoming = buildTask(id: 'a', updatedAt: 100, createdAt: 11);

    final resolved = resolveByLww(current, incoming);

    expect(resolved.createdAt, 11);
  });

  test('論理削除タスクは30日を超えたらpurge対象', () {
    final now = DateTime(2026, 3, 30);
    final oldDeleted = buildTask(
      id: 'a',
      updatedAt: 1,
      createdAt: 1,
      isDeleted: true,
      deletedAt: DateTime(2026, 2, 27).millisecondsSinceEpoch,
    );
    final recentDeleted = buildTask(
      id: 'b',
      updatedAt: 1,
      createdAt: 1,
      isDeleted: true,
      deletedAt: DateTime(2026, 3, 10).millisecondsSinceEpoch,
    );

    expect(shouldPurgeDeletedTask(oldDeleted, now), isTrue);
    expect(shouldPurgeDeletedTask(recentDeleted, now), isFalse);
  });
}
