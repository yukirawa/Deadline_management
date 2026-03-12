import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/models/task_type.dart';
import 'package:kigenkanri/models/user_settings.dart';
import 'package:kigenkanri/screens/add_task_page.dart';
import 'package:kigenkanri/services/auth_service.dart';
import 'package:kigenkanri/services/notification_service.dart';
import 'package:kigenkanri/services/task_repository.dart';
import 'package:kigenkanri/utils/task_filter_utils.dart';
import 'package:kigenkanri/widgets/notification_preferences_form.dart';
import 'package:kigenkanri/widgets/task_card.dart';

class TaskHomePage extends StatefulWidget {
  const TaskHomePage({
    super.key,
    required this.user,
    required this.authService,
    required this.taskRepository,
    required this.notificationService,
  });

  final User user;
  final AuthService authService;
  final TaskRepository taskRepository;
  final NotificationService notificationService;

  @override
  State<TaskHomePage> createState() => _TaskHomePageState();
}

class _TaskHomePageState extends State<TaskHomePage> {
  final TextEditingController _queryController = TextEditingController();

  late Future<void> _prepareFuture;
  int _tabIndex = 0;
  String _query = '';
  String? _typeFilter;
  TaskDoneFilter _doneFilter = TaskDoneFilter.all;

  @override
  void initState() {
    super.initState();
    _prepareFuture = _prepare();
    _queryController.addListener(() {
      setState(() {
        _query = _queryController.text;
      });
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    widget.notificationService.unbindUser();
    super.dispose();
  }

  Future<void> _prepare() async {
    final uid = widget.user.uid;
    await widget.taskRepository.prepareForUser(uid);
    await widget.notificationService.bindUser(uid);
  }

  Future<void> _openTaskForm({Task? task}) async {
    final input = await Navigator.of(context).push<TaskFormResult>(
      MaterialPageRoute(builder: (_) => TaskFormPage(initialTask: task)),
    );
    if (!mounted || input == null) {
      return;
    }

    try {
      if (task == null) {
        await widget.taskRepository.createTask(
          uid: widget.user.uid,
          subject: input.subject,
          type: input.type,
          title: input.title,
          dueDate: input.dueDate,
          dueTime: input.dueTime,
        );
      } else {
        await widget.taskRepository.updateTask(
          uid: widget.user.uid,
          original: task,
          subject: input.subject,
          type: input.type,
          title: input.title,
          dueDate: input.dueDate,
          dueTime: input.dueTime,
        );
      }
    } catch (error) {
      _showError('タスクの保存に失敗しました: $error');
    }
  }

  Future<void> _toggleDone(Task task, bool done) async {
    try {
      await widget.taskRepository.toggleDone(
        uid: widget.user.uid,
        task: task,
        done: done,
      );
    } catch (error) {
      _showError('完了状態の更新に失敗しました: $error');
    }
  }

  Future<void> _softDelete(Task task) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('タスクを削除'),
          content: const Text('このタスクをゴミ箱に移動します。後から復元できます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await widget.taskRepository.softDeleteTask(
        uid: widget.user.uid,
        task: task,
      );
    } catch (error) {
      _showError('削除に失敗しました: $error');
    }
  }

  Future<void> _restore(Task task) async {
    try {
      await widget.taskRepository.restoreTask(uid: widget.user.uid, task: task);
    } catch (error) {
      _showError('復元に失敗しました: $error');
    }
  }

  Future<void> _hardDelete(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('完全に削除'),
          content: const Text('このタスクを完全に削除します。元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('完全削除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.taskRepository.hardDeleteTask(
        uid: widget.user.uid,
        task: task,
      );
    } catch (error) {
      _showError('完全削除に失敗しました: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _prepareFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('初期化エラー')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('初期化に失敗しました: ${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _prepareFuture = _prepare();
                        });
                      },
                      child: const Text('再試行'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return StreamBuilder<List<Task>>(
          stream: widget.taskRepository.watchAllTasks(widget.user.uid),
          builder: (context, taskSnapshot) {
            if (taskSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final tasks = taskSnapshot.data ?? const <Task>[];
            final activeTasks = tasks.where((task) => !task.isDeleted).toList();
            final deletedTasks = tasks.where((task) => task.isDeleted).toList();
            final filteredTasks = filterTasks(
              tasks: activeTasks,
              query: _query,
              type: _typeFilter,
              doneFilter: _doneFilter,
            );

            return Scaffold(
              appBar: AppBar(
                title: Text(_titleForTab),
                actions: [
                  if (_tabIndex == 0)
                    IconButton(
                      onPressed: () => _openTaskForm(),
                      icon: const Icon(Icons.add),
                      tooltip: '追加',
                    ),
                ],
              ),
              body: IndexedStack(
                index: _tabIndex,
                children: [
                  _TaskListTab(
                    queryController: _queryController,
                    selectedType: _typeFilter,
                    doneFilter: _doneFilter,
                    onTypeChanged: (value) {
                      setState(() {
                        _typeFilter = value;
                      });
                    },
                    onDoneFilterChanged: (value) {
                      setState(() {
                        _doneFilter = value;
                      });
                    },
                    tasks: filteredTasks,
                    onDoneChanged: _toggleDone,
                    onEdit: (task) => _openTaskForm(task: task),
                    onDelete: _softDelete,
                  ),
                  _TrashTab(
                    tasks: deletedTasks,
                    onRestore: _restore,
                    onHardDelete: _hardDelete,
                  ),
                  _SettingsTab(
                    user: widget.user,
                    taskRepository: widget.taskRepository,
                    notificationService: widget.notificationService,
                    authService: widget.authService,
                    onError: _showError,
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tabIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _tabIndex = index;
                  });
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.list_alt),
                    label: 'タスク',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.delete_outline),
                    label: 'ゴミ箱',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings),
                    label: '設定',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String get _titleForTab {
    switch (_tabIndex) {
      case 1:
        return 'ゴミ箱';
      case 2:
        return '設定';
      default:
        return '締切レーダー';
    }
  }
}

class _TaskListTab extends StatelessWidget {
  const _TaskListTab({
    required this.queryController,
    required this.selectedType,
    required this.doneFilter,
    required this.onTypeChanged,
    required this.onDoneFilterChanged,
    required this.tasks,
    required this.onDoneChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final TextEditingController queryController;
  final String? selectedType;
  final TaskDoneFilter doneFilter;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<TaskDoneFilter> onDoneFilterChanged;
  final List<Task> tasks;
  final Future<void> Function(Task task, bool done) onDoneChanged;
  final Future<void> Function(Task task) onEdit;
  final Future<void> Function(Task task) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: queryController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '検索',
                      hintText: '科目または内容',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: selectedType,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '種別',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('すべて'),
                            ),
                            ...TaskType.values.map(
                              (type) => DropdownMenuItem<String?>(
                                value: type.value,
                                child: Text(type.label),
                              ),
                            ),
                          ],
                          onChanged: onTypeChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<TaskDoneFilter>(
                          initialValue: doneFilter,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '状態',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: TaskDoneFilter.all,
                              child: Text('すべて'),
                            ),
                            DropdownMenuItem(
                              value: TaskDoneFilter.open,
                              child: Text('未完了'),
                            ),
                            DropdownMenuItem(
                              value: TaskDoneFilter.done,
                              child: Text('完了'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            onDoneFilterChanged(value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? const Center(child: Text('表示できるタスクがありません'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return TaskCard(
                      task: task,
                      onDoneChanged: (done) => onDoneChanged(task, done),
                      onEdit: () => onEdit(task),
                      onDelete: () => onDelete(task),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TrashTab extends StatelessWidget {
  const _TrashTab({
    required this.tasks,
    required this.onRestore,
    required this.onHardDelete,
  });

  final List<Task> tasks;
  final Future<void> Function(Task task) onRestore;
  final Future<void> Function(Task task) onHardDelete;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Center(child: Text('ゴミ箱は空です'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TaskCard(
          task: task,
          showCheckbox: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => onRestore(task),
                icon: const Icon(Icons.restore_from_trash),
                tooltip: '復元',
              ),
              IconButton(
                onPressed: () => onHardDelete(task),
                icon: const Icon(Icons.delete_forever),
                tooltip: '完全削除',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.user,
    required this.taskRepository,
    required this.notificationService,
    required this.authService,
    required this.onError,
  });

  final User user;
  final TaskRepository taskRepository;
  final NotificationService notificationService;
  final AuthService authService;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserSettings>(
      stream: taskRepository.watchUserSettings(user.uid),
      builder: (context, snapshot) {
        final settings = snapshot.data ?? UserSettings.defaults();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_circle),
                title: Text(user.displayName ?? 'Googleユーザー'),
                subtitle: Text(user.email ?? ''),
              ),
            ),
            const SizedBox(height: 12),
            NotificationPreferencesForm(
              initialSettings: settings,
              onSave: (draft) async {
                try {
                  await notificationService.updateNotificationPreferences(
                    uid: user.uid,
                    previousSettings: settings,
                    nextSettings: draft,
                  );
                } catch (error) {
                  onError('通知設定の保存に失敗しました: $error');
                  rethrow;
                }
              },
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () async {
                try {
                  await authService.signOut();
                } catch (error) {
                  onError('ログアウトに失敗しました: $error');
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('ログアウト'),
            ),
          ],
        );
      },
    );
  }
}
