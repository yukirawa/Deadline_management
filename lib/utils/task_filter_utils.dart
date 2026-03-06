import 'package:kigenkanri/models/task.dart';

enum TaskDoneFilter { all, open, done }

List<Task> filterTasks({
  required Iterable<Task> tasks,
  required String query,
  required String? type,
  required TaskDoneFilter doneFilter,
}) {
  final normalizedQuery = query.trim().toLowerCase();

  return tasks.where((task) {
    if (type != null && type.isNotEmpty && task.type != type) {
      return false;
    }

    if (doneFilter == TaskDoneFilter.open && task.done) {
      return false;
    }
    if (doneFilter == TaskDoneFilter.done && !task.done) {
      return false;
    }

    if (normalizedQuery.isEmpty) {
      return true;
    }

    final target = '${task.subject} ${task.title}'.toLowerCase();
    return target.contains(normalizedQuery);
  }).toList();
}
