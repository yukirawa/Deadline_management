import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:kigenkanri/models/notification_rules.dart';
import 'package:kigenkanri/models/user_settings.dart';
import 'package:kigenkanri/services/task_storage_service.dart';
import 'package:uuid/uuid.dart';

const List<String> supportedTimezones = [
  'Asia/Tokyo',
  'UTC',
  'America/Los_Angeles',
  'America/New_York',
  'Europe/London',
  'Europe/Paris',
  'Asia/Singapore',
  'Australia/Sydney',
];

class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    TaskStorageService? localStorage,
    Uuid? uuid,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _localStorage = localStorage ?? TaskStorageService(),
       _uuid = uuid ?? const Uuid();

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final TaskStorageService _localStorage;
  final Uuid _uuid;

  StreamSubscription<String>? _tokenSubscription;

  Future<void> bindUser(String uid) async {
    await registerDeviceToken(uid);
    await _tokenSubscription?.cancel();
    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(registerDeviceToken(uid, token: token)),
    );
  }

  Future<void> unbindUser() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
  }

  Future<NotificationSettings> requestPermission() {
    return _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> updateNotificationPreferences({
    required String uid,
    required UserSettings previousSettings,
    required UserSettings nextSettings,
  }) async {
    if (!supportedTimezones.contains(nextSettings.timezone)) {
      throw ArgumentError.value(
        nextSettings.timezone,
        'timezone',
        'Unsupported timezone',
      );
    }

    final deadlineRuleError = validateDeadlineReminderRules(
      nextSettings.deadlineReminderRules,
    );
    if (deadlineRuleError != null) {
      throw ArgumentError(deadlineRuleError);
    }

    final dailyRuleError = validateDailySummaryRules(
      nextSettings.dailySummaryRules,
    );
    if (dailyRuleError != null) {
      throw ArgumentError(dailyRuleError);
    }

    if (!previousSettings.notificationsEnabled &&
        nextSettings.notificationsEnabled) {
      final permission = await requestPermission();
      final granted =
          permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional;
      if (!granted) {
        throw StateError('Notification permission was not granted.');
      }
    }

    if (nextSettings.notificationsEnabled) {
      await registerDeviceToken(uid);
    }

    final payload = nextSettings.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _profileRef(uid).set(payload.toJson(), SetOptions(merge: true));
  }

  Future<void> registerDeviceToken(String uid, {String? token}) async {
    String? resolvedToken;
    try {
      resolvedToken = token ?? await _resolveToken();
    } catch (_) {
      return;
    }
    if (resolvedToken == null || resolvedToken.isEmpty) {
      return;
    }
    final deviceId = await _resolveDeviceId();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _devicesRef(uid).doc(deviceId).set({
      'token': resolvedToken,
      'platform': _platformName,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  Future<String?> _resolveToken() {
    return _messaging.getToken(
      vapidKey: kIsWeb && _webPushCertKey.isNotEmpty ? _webPushCertKey : null,
    );
  }

  Future<String> _resolveDeviceId() async {
    final cached = await _localStorage.getDeviceId();
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final generated = _uuid.v4();
    await _localStorage.setDeviceId(generated);
    return generated;
  }

  String get _platformName {
    if (kIsWeb) {
      return 'web';
    }
    return 'android';
  }

  CollectionReference<Map<String, dynamic>> _devicesRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('devices');
  }

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('profile');
  }
}

const String _webPushCertKey = String.fromEnvironment(
  'WEB_PUSH_CERT_KEY',
  defaultValue: '',
);
