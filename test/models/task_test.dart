import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/task.dart';

void main() {
  test('TaskのJSON変換が往復一致する', () {
    final task = Task(
      id: 'id-1',
      subject: '数学',
      type: 'assignment',
      title: 'ワーク p.10-12',
      dueDate: '2026-03-10',
      done: false,
      createdAt: 1,
      updatedAt: 2,
    );

    final restored = Task.fromJson(task.toJson());

    expect(restored.id, task.id);
    expect(restored.subject, task.subject);
    expect(restored.type, task.type);
    expect(restored.title, task.title);
    expect(restored.dueDate, task.dueDate);
    expect(restored.done, task.done);
    expect(restored.createdAt, task.createdAt);
    expect(restored.updatedAt, task.updatedAt);
  });
}
