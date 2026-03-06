import 'package:flutter/material.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/screens/add_task_page.dart';
import 'package:kigenkanri/services/task_service.dart';
import 'package:kigenkanri/services/task_storage_service.dart';
import 'package:kigenkanri/widgets/task_card.dart';

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final TaskStorageService _taskStorageService = TaskStorageService();
  late final TaskService _taskService;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _taskService = TaskService();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await _taskStorageService.loadTasks();
      if (!mounted) {
        return;
      }
      setState(() {
        _taskService.replaceAll(tasks);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'タスクの読み込みに失敗しました。';
      });
    }
  }

  Future<void> _saveTasks() async {
    await _taskStorageService.saveTasks(_taskService.tasks);
  }

  Future<void> _openAddTaskPage() async {
    final input = await Navigator.of(context).push<AddTaskInput>(
      MaterialPageRoute(builder: (_) => const AddTaskPage()),
    );

    if (!mounted || input == null) {
      return;
    }

    setState(() {
      _taskService.addTask(
        subject: input.subject,
        type: input.type,
        title: input.title,
        dueDate: input.dueDate,
      );
    });

    try {
      await _saveTasks();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存に失敗しました。再度お試しください。')));
    }
  }

  Future<void> _toggleDone(Task task, bool done) async {
    setState(() {
      _taskService.toggleDone(taskId: task.id, done: done);
    });

    try {
      await _saveTasks();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('更新の保存に失敗しました。再度お試しください。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _taskService.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('締切レーダー'),
        actions: [
          IconButton(
            onPressed: _openAddTaskPage,
            icon: const Icon(Icons.add),
            tooltip: '追加',
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorMessage!),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _loadTasks();
                      },
                      child: const Text('再読み込み'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (tasks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('タスクはまだありません。右上の＋から追加してください。'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: tasks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return TaskCard(
                task: task,
                onDoneChanged: (done) => _toggleDone(task, done),
              );
            },
          );
        },
      ),
    );
  }
}
