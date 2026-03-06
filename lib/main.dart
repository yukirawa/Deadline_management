import 'package:flutter/material.dart';
import 'package:kigenkanri/screens/task_list_page.dart';

void main() {
  runApp(const DeadlineRadarApp());
}

class DeadlineRadarApp extends StatelessWidget {
  const DeadlineRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '締切レーダー',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TaskListPage(),
    );
  }
}
