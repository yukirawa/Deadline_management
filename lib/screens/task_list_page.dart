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
  static const double _desktopBreakpoint = 1024;
  static const double _desktopContentMaxWidth = 1440;
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= _desktopBreakpoint;

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
                  if (_tabIndex == 0 && !isDesktop)
                    IconButton(
                      onPressed: () => _openTaskForm(),
                      icon: const Icon(Icons.add),
                      tooltip: '追加',
                    ),
                ],
              ),
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _desktopContentMaxWidth,
                    ),
                    child: isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  16,
                                  0,
                                  16,
                                ),
                                child: NavigationRail(
                                  selectedIndex: _tabIndex,
                                  onDestinationSelected: (index) {
                                    setState(() {
                                      _tabIndex = index;
                                    });
                                  },
                                  labelType: NavigationRailLabelType.all,
                                  leading: Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: FilledButton.icon(
                                      onPressed: _tabIndex == 0
                                          ? () => _openTaskForm()
                                          : null,
                                      icon: const Icon(Icons.add),
                                      label: const Text('追加'),
                                    ),
                                  ),
                                  destinations: const [
                                    NavigationRailDestination(
                                      icon: Icon(Icons.list_alt),
                                      label: Text('タスク'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(Icons.delete_outline),
                                      label: Text('ゴミ箱'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(Icons.settings),
                                      label: Text('設定'),
                                    ),
                                  ],
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(child: _buildTabBody(filteredTasks, deletedTasks)),
                            ],
                          )
                        : _buildTabBody(filteredTasks, deletedTasks),
                  ),
                ),
              ),
              bottomNavigationBar: isDesktop
                  ? null
                  : NavigationBar(
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

  Widget _buildTabBody(List<Task> filteredTasks, List<Task> deletedTasks) {
    return IndexedStack(
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
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;

    if (!isDesktop) {
      return Column(
        children: [
          _TaskFilterPanel(
            queryController: queryController,
            selectedType: selectedType,
            doneFilter: doneFilter,
            onTypeChanged: onTypeChanged,
            onDoneFilterChanged: onDoneFilterChanged,
            taskCount: tasks.length,
            isDesktop: false,
          ),
          const SizedBox(height: 12),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: _TaskFilterPanel(
              queryController: queryController,
              selectedType: selectedType,
              doneFilter: doneFilter,
              onTypeChanged: onTypeChanged,
              onDoneFilterChanged: onDoneFilterChanged,
              taskCount: tasks.length,
              isDesktop: true,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(child: _buildDesktopTaskList()),
        ],
      ),
    );
  }

  Widget _buildDesktopTaskList() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: tasks.isEmpty
          ? const Center(child: Text('表示できるタスクがありません'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
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
    );
  }
}

class _TaskFilterPanel extends StatelessWidget {
  const _TaskFilterPanel({
    required this.queryController,
    required this.selectedType,
    required this.doneFilter,
    required this.onTypeChanged,
    required this.onDoneFilterChanged,
    required this.taskCount,
    required this.isDesktop,
  });

  final TextEditingController queryController;
  final String? selectedType;
  final TaskDoneFilter doneFilter;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<TaskDoneFilter> onDoneFilterChanged;
  final int taskCount;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.all(isDesktop ? 16 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (isDesktop) ...[
            Text('絞り込み', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '表示件数: $taskCount 件',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
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
    );

    if (!isDesktop) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Card(child: content),
      );
    }

    return Card(
      child: content,
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
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;

    if (tasks.isEmpty) {
      return const Center(child: Text('ゴミ箱は空です'));
    }

    if (!isDesktop) {
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

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
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
        final isDesktop = MediaQuery.sizeOf(context).width >= 1024;

        if (!isDesktop) {
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
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.all(24),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
