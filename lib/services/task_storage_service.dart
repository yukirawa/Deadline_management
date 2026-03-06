import 'dart:convert';

import 'package:kigenkanri/models/task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskStorageService {
  static const String tasksKey = 'tasks_v1';

  Future<List<Task>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(tasksKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              Task.fromJson(item.map((key, value) => MapEntry('$key', value))),
        )
        .toList();
  }

  Future<void> saveTasks(List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(tasks.map((task) => task.toJson()).toList());
    await prefs.setString(tasksKey, payload);
  }
}
