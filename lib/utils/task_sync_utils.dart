import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/utils/deadline_utils.dart';

Task resolveByLww(Task current, Task incoming) {
  if (incoming.updatedAt > current.updatedAt) {
    return incoming;
  }
  if (incoming.updatedAt < current.updatedAt) {
    return current;
  }

  if (incoming.createdAt >= current.createdAt) {
    return incoming;
  }
  return current;
}

int compareTaskForDisplay(Task left, Task right) {
  if (left.isDeleted != right.isDeleted) {
    return left.isDeleted ? 1 : -1;
  }

  if (left.isDeleted && right.isDeleted) {
    final leftDeletedAt = left.deletedAt ?? 0;
    final rightDeletedAt = right.deletedAt ?? 0;
    return rightDeletedAt.compareTo(leftDeletedAt);
  }

  if (left.done != right.done) {
    return left.done ? 1 : -1;
  }

  final dueDateCompare = resolveDueDateTime(
    left.dueDate,
    dueTime: left.dueTime,
  ).compareTo(resolveDueDateTime(right.dueDate, dueTime: right.dueTime));
  if (dueDateCompare != 0) {
    return dueDateCompare;
  }

  return left.createdAt.compareTo(right.createdAt);
}

bool shouldPurgeDeletedTask(
  Task task,
  DateTime now, {
  Duration retention = const Duration(days: 30),
}) {
  if (!task.isDeleted || task.deletedAt == null) {
    return false;
  }
  final cutoff = now.millisecondsSinceEpoch - retention.inMilliseconds;
  return task.deletedAt! <= cutoff;
}
