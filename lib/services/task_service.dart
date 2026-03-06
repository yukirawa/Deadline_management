import 'dart:collection';

import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/utils/deadline_utils.dart';
import 'package:uuid/uuid.dart';

class TaskService {
  TaskService({List<Task>? initialTasks, Uuid? uuid})
    : _uuid = uuid ?? const Uuid(),
      _tasks = [...?initialTasks] {
    sortTasks();
  }

  final Uuid _uuid;
  final List<Task> _tasks;

  UnmodifiableListView<Task> get tasks => UnmodifiableListView(_tasks);

  void replaceAll(List<Task> tasks) {
    _tasks
      ..clear()
      ..addAll(tasks);
    sortTasks();
  }

  Task addTask({
    required String subject,
    required String type,
    required String title,
    required String dueDate,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final task = Task(
      id: _uuid.v4(),
      subject: subject,
      type: type,
      title: title,
      dueDate: dueDate,
      done: false,
      createdAt: now,
      updatedAt: now,
    );
    _tasks.add(task);
    sortTasks();
    return task;
  }

  bool toggleDone({required String taskId, required bool done}) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) {
      return false;
    }

    _tasks[index] = _tasks[index].copyWith(
      done: done,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    sortTasks();
    return true;
  }

  void sortTasks() {
    _tasks.sort(_compareTask);
  }

  int _compareTask(Task left, Task right) {
    if (left.done != right.done) {
      return left.done ? 1 : -1;
    }

    final dueDateCompare = parseStorageDate(
      left.dueDate,
    ).compareTo(parseStorageDate(right.dueDate));
    if (dueDateCompare != 0) {
      return dueDateCompare;
    }

    return left.createdAt.compareTo(right.createdAt);
  }
}
