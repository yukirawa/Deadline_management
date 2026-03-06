import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/services/task_service.dart';

void main() {
  Task buildTask({
    required String id,
    required String dueDate,
    required bool done,
    required int createdAt,
  }) {
    return Task(
      id: id,
      subject: '数学',
      type: 'assignment',
      title: '課題',
      dueDate: dueDate,
      done: done,
      createdAt: createdAt,
      updatedAt: createdAt,
      isDeleted: false,
      deletedAt: null,
    );
  }

  test('並び順は未完了優先、締切昇順、同日ならcreatedAt昇順', () {
    final service = TaskService(
      initialTasks: [
        buildTask(id: '3', dueDate: '2026-03-08', done: true, createdAt: 3),
        buildTask(id: '2', dueDate: '2026-03-07', done: false, createdAt: 2),
        buildTask(id: '1', dueDate: '2026-03-07', done: false, createdAt: 1),
        buildTask(id: '4', dueDate: '2026-03-05', done: false, createdAt: 4),
      ],
    );

    expect(service.tasks.map((task) => task.id), ['4', '1', '2', '3']);
  });

  test('addTaskで未完了タスクが追加されてソートされる', () {
    final service = TaskService(
      initialTasks: [
        buildTask(id: 'a', dueDate: '2026-03-10', done: false, createdAt: 1),
      ],
    );

    final added = service.addTask(
      subject: '英語',
      type: 'quiz',
      title: '単語テスト',
      dueDate: '2026-03-07',
    );

    expect(added.done, false);
    expect(added.dueDate, '2026-03-07');
    expect(service.tasks.first.id, added.id);
  });

  test('toggleDoneで完了状態が変わり、完了タスクは下に移動する', () {
    final service = TaskService(
      initialTasks: [
        buildTask(id: 'a', dueDate: '2026-03-07', done: false, createdAt: 1),
        buildTask(id: 'b', dueDate: '2026-03-08', done: false, createdAt: 2),
      ],
    );

    final changed = service.toggleDone(taskId: 'a', done: true);

    expect(changed, true);
    expect(service.tasks.map((task) => task.id), ['b', 'a']);
    expect(service.tasks.last.done, true);
  });
}
