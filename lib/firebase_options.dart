import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are configured only for web and android.',
        );
    }
  }

  static bool get isConfigured {
    final options = currentPlatform;
    return options.apiKey.isNotEmpty &&
        options.appId.isNotEmpty &&
        options.messagingSenderId.isNotEmpty &&
        options.projectId.isNotEmpty;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY', defaultValue: ''),
    appId: String.fromEnvironment('FIREBASE_WEB_APP_ID', defaultValue: ''),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '',
    ),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: ''),
    authDomain: String.fromEnvironment(
      'FIREBASE_AUTH_DOMAIN',
      defaultValue: '',
    ),
    storageBucket: String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: '',
    ),
    measurementId: String.fromEnvironment(
      'FIREBASE_WEB_MEASUREMENT_ID',
      defaultValue: '',
    ),
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIREBASE_ANDROID_API_KEY',
      defaultValue: '',
    ),
    appId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID', defaultValue: ''),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '',
    ),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: ''),
    storageBucket: String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: '',
    ),
  );
}
