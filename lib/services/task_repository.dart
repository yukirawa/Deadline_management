import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/models/user_settings.dart';
import 'package:kigenkanri/services/task_storage_service.dart';
import 'package:kigenkanri/utils/task_sync_utils.dart';
import 'package:uuid/uuid.dart';

class TaskRepository {
  TaskRepository({
    FirebaseFirestore? firestore,
    TaskStorageService? localStorage,
    Uuid? uuid,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _localStorage = localStorage ?? TaskStorageService(),
       _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final TaskStorageService _localStorage;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> _tasksRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('tasks');
  }

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('profile');
  }

  CollectionReference<Map<String, dynamic>> notificationSlotsRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notification_slots');
  }

  Stream<List<Task>> watchAllTasks(String uid) {
    return _tasksRef(uid).snapshots().map((snapshot) {
      final tasks = snapshot.docs
          .map((doc) => Task.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
      tasks.sort(compareTaskForDisplay);
      return tasks;
    });
  }

  Stream<UserSettings> watchUserSettings(String uid) {
    return _profileRef(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return UserSettings.defaults();
      }
      return UserSettings.fromJson(snapshot.data()!);
    });
  }

  Future<UserSettings> prepareForUser(String uid) async {
    var settings = await ensureUserSettings(uid);

    if (!settings.migratedLocalV1) {
      await _importLocalTasks(uid);
      settings = settings.copyWith(
        migratedLocalV1: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _profileRef(uid).set(settings.toJson(), SetOptions(merge: true));
    }

    await purgeSoftDeletedTasks(uid);
    return settings;
  }

  Future<UserSettings> ensureUserSettings(String uid) async {
    final ref = _profileRef(uid);
    final snapshot = await ref.get();
    if (snapshot.exists) {
      return UserSettings.fromJson(snapshot.data()!);
    }
    final defaults = UserSettings.defaults();
    await ref.set(defaults.toJson(), SetOptions(merge: true));
    return defaults;
  }

  Future<Task> createTask({
    required String uid,
    required String subject,
    required String type,
    required String title,
    required String dueDate,
  }) async {
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
      isDeleted: false,
      deletedAt: null,
    );
    await _upsertWithLww(uid, task);
    return task;
  }

  Future<void> updateTask({
    required String uid,
    required Task original,
    required String subject,
    required String type,
    required String title,
    required String dueDate,
  }) async {
    final candidate = original.copyWith(
      subject: subject,
      type: type,
      title: title,
      dueDate: dueDate,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _upsertWithLww(uid, candidate);
  }

  Future<void> toggleDone({
    required String uid,
    required Task task,
    required bool done,
  }) async {
    final candidate = task.copyWith(
      done: done,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _upsertWithLww(uid, candidate);
  }

  Future<void> softDeleteTask({required String uid, required Task task}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final candidate = task.copyWith(
      isDeleted: true,
      deletedAt: now,
      updatedAt: now,
    );
    await _upsertWithLww(uid, candidate);
  }

  Future<void> restoreTask({required String uid, required Task task}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final candidate = task.copyWith(
      isDeleted: false,
      clearDeletedAt: true,
      updatedAt: now,
    );
    await _upsertWithLww(uid, candidate);
  }

  Future<void> hardDeleteTask({required String uid, required Task task}) async {
    await _tasksRef(uid).doc(task.id).delete();
  }

  Future<void> purgeSoftDeletedTasks(String uid) async {
    final now = DateTime.now();
    final snapshot = await _tasksRef(
      uid,
    ).where('isDeleted', isEqualTo: true).get();
    if (snapshot.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    var hasDelete = false;
    for (final doc in snapshot.docs) {
      final task = Task.fromJson({...doc.data(), 'id': doc.id});
      if (!shouldPurgeDeletedTask(task, now)) {
        continue;
      }
      batch.delete(doc.reference);
      hasDelete = true;
    }

    if (hasDelete) {
      await batch.commit();
    }
  }

  Future<void> _upsertWithLww(String uid, Task candidate) async {
    final ref = _tasksRef(uid).doc(candidate.id);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        transaction.set(ref, candidate.toJson());
        return;
      }

      final current = Task.fromJson({...snapshot.data()!, 'id': snapshot.id});
      final resolved = resolveByLww(current, candidate);
      if (resolved == current) {
        return;
      }
      transaction.set(ref, resolved.toJson());
    });
  }

  Future<void> _importLocalTasks(String uid) async {
    final alreadyMigrated = await _localStorage.isMigratedForUser(uid);
    if (alreadyMigrated) {
      return;
    }
    final localTasks = await _localStorage.loadTasks();
    for (final task in localTasks) {
      final normalized = task.copyWith(
        isDeleted: task.isDeleted,
        deletedAt: task.deletedAt,
      );
      await _upsertWithLww(uid, normalized);
    }
    await _localStorage.markMigratedForUser(uid);
  }
}
