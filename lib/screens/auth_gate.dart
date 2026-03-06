import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kigenkanri/screens/sign_in_page.dart';
import 'package:kigenkanri/screens/task_list_page.dart';
import 'package:kigenkanri/services/auth_service.dart';
import 'package:kigenkanri/services/notification_service.dart';
import 'package:kigenkanri/services/task_repository.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authService,
    required this.taskRepository,
    required this.notificationService,
  });

  final AuthService authService;
  final TaskRepository taskRepository;
  final NotificationService notificationService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _redirectFuture;

  @override
  void initState() {
    super.initState();
    _redirectFuture = widget.authService.resolveRedirectResultIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _redirectFuture,
      builder: (context, redirectSnapshot) {
        if (redirectSnapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return StreamBuilder<User?>(
          stream: widget.authService.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final user = snapshot.data;
            if (user == null) {
              return SignInPage(authService: widget.authService);
            }

            return TaskHomePage(
              user: user,
              authService: widget.authService,
              taskRepository: widget.taskRepository,
              notificationService: widget.notificationService,
            );
          },
        );
      },
    );
  }
}
