import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:kigenkanri/firebase_options.dart';
import 'package:kigenkanri/screens/app_bootstrap_page.dart';
import 'package:kigenkanri/screens/auth_gate.dart';
import 'package:kigenkanri/screens/firebase_setup_page.dart';
import 'package:kigenkanri/services/auth_service.dart';
import 'package:kigenkanri/services/notification_service.dart';
import 'package:kigenkanri/services/task_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final setupError = await _initializeFirebase();
  runApp(DeadlineRadarApp(setupError: setupError));
}

Future<String?> _initializeFirebase() async {
  if (!DefaultFirebaseOptions.isConfigured) {
    return 'Firebase options are not configured. '
        'Set required --dart-define values before launch.';
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    return 'Firebase initialization failed: $error';
  }
  return null;
}

class DeadlineRadarApp extends StatelessWidget {
  const DeadlineRadarApp({super.key, this.setupError});

  final String? setupError;

  @override
  Widget build(BuildContext context) {
    final appHome = setupError == null
        ? AuthGate(
            authService: AuthService(),
            taskRepository: TaskRepository(),
            notificationService: NotificationService(),
          )
        : FirebaseSetupPage(message: setupError!);

    return MaterialApp(
      title: '締切レーダー',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: AppBootstrapPage(child: appHome),
    );
  }
}
