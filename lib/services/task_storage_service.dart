import 'dart:convert';

import 'package:kigenkanri/models/task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskStorageService {
  static const String tasksKey = 'tasks_v1';
  static const String migratedKeyPrefix = 'tasks_v1_migrated_';
  static const String deviceIdKey = 'device_id_v1';

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

  Future<bool> isMigratedForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$migratedKeyPrefix$uid') ?? false;
  }

  Future<void> markMigratedForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$migratedKeyPrefix$uid', true);
  }

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(deviceIdKey);
  }

  Future<void> setDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(deviceIdKey, deviceId);
  }
}
