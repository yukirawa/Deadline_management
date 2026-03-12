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
  String? dueTime,
}) {
  return Task(
    id: id,
    subject: '数学',
    type: 'assignment',
    title: '課題',
    dueDate: dueDate,
    dueTime: dueTime,
    done: done,
    createdAt: createdAt,
    updatedAt: updatedAt,
    isDeleted: isDeleted,
    deletedAt: deletedAt,
  );
}

void main() {
  test('LWW は updatedAt が新しいタスクを採用する', () {
    final current = buildTask(id: 'a', updatedAt: 100, createdAt: 10);
    final incoming = buildTask(id: 'a', updatedAt: 200, createdAt: 9);

    final resolved = resolveByLww(current, incoming);

    expect(resolved.updatedAt, 200);
  });

  test('updatedAt が同一なら createdAt が大きい方を採用する', () {
    final current = buildTask(id: 'a', updatedAt: 100, createdAt: 10);
    final incoming = buildTask(id: 'a', updatedAt: 100, createdAt: 11);

    final resolved = resolveByLww(current, incoming);

    expect(resolved.createdAt, 11);
  });

  test('同日のタスクは締切時刻順に並ぶ', () {
    final early = buildTask(
      id: 'early',
      updatedAt: 1,
      createdAt: 1,
      dueDate: '2026-03-10',
      dueTime: '09:00',
    );
    final late = buildTask(
      id: 'late',
      updatedAt: 1,
      createdAt: 2,
      dueDate: '2026-03-10',
      dueTime: null,
    );

    expect(compareTaskForDisplay(early, late), lessThan(0));
  });

  test('論理削除タスクは30日を超えたら purge 対象', () {
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
