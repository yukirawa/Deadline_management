import 'package:flutter/material.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/models/task_type.dart';
import 'package:kigenkanri/utils/deadline_utils.dart';

class TaskFormResult {
  const TaskFormResult({
    required this.subject,
    required this.type,
    required this.title,
    required this.dueDate,
    required this.dueTime,
  });

  final String subject;
  final String type;
  final String title;
  final String dueDate;
  final String? dueTime;
}

class TaskFormPage extends StatefulWidget {
  const TaskFormPage({super.key, this.initialTask});

  final Task? initialTask;

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _titleController = TextEditingController();

  late TaskType _selectedType;
  DateTime? _selectedDate;
  String? _selectedTime;
  bool _showDateError = false;

  bool get _isEdit => widget.initialTask != null;

  @override
  void initState() {
    super.initState();
    final task = widget.initialTask;
    if (task == null) {
      _selectedType = TaskType.assignment;
      return;
    }
    _subjectController.text = task.subject;
    _titleController.text = task.title;
    _selectedType = TaskType.fromValue(task.type);
    _selectedDate = parseStorageDate(task.dueDate);
    _selectedTime = task.dueTime;
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 10),
    );

    if (!mounted || pickedDate == null) {
      return;
    }

    setState(() {
      _selectedDate = pickedDate;
      _showDateError = false;
    });
  }

  Future<void> _selectTime() async {
    final pickedTime = await showDialog<String?>(
      context: context,
      builder: (context) {
        return _QuarterHourTimeDialog(initialValue: _selectedTime);
      },
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    setState(() {
      _selectedTime = pickedTime.isEmpty ? null : pickedTime;
    });
  }

  void _submit() {
    final isFormValid = _formKey.currentState?.validate() ?? false;
    final hasDate = _selectedDate != null;

    setState(() {
      _showDateError = !hasDate;
    });

    if (!isFormValid || !hasDate) {
      return;
    }

    Navigator.of(context).pop(
      TaskFormResult(
        subject: _subjectController.text.trim(),
        type: _selectedType.value,
        title: _titleController.text.trim(),
        dueDate: formatStorageDate(_selectedDate!),
        dueTime: _selectedTime,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'タスク編集' : 'タスク追加')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: '科目',
                  hintText: '例: 数学',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '科目を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskType>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: '種別',
                  border: OutlineInputBorder(),
                ),
                items: TaskType.values
                    .map(
                      (type) => DropdownMenuItem<TaskType>(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedType = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '内容',
                  hintText: '例: ワーク p.12-15',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '内容を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: '締切日',
                  border: const OutlineInputBorder(),
                  errorText: _showDateError ? '締切日を選択してください' : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedDate == null
                            ? '未選択'
                            : formatDisplayDate(
                                formatStorageDate(_selectedDate!),
                              ),
                      ),
                    ),
                    TextButton(
                      onPressed: _selectDate,
                      child: const Text('日付を選択'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '締切時刻',
                  border: OutlineInputBorder(),
                  helperText: '任意。15分単位で設定できます',
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(dueTimeLabel(_selectedTime))),
                    TextButton(
                      onPressed: _selectTime,
                      child: const Text('時刻を設定'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('キャンセル'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(_isEdit ? '更新' : '保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuarterHourTimeDialog extends StatefulWidget {
  const _QuarterHourTimeDialog({this.initialValue});

  final String? initialValue;

  @override
  State<_QuarterHourTimeDialog> createState() => _QuarterHourTimeDialogState();
}

class _QuarterHourTimeDialogState extends State<_QuarterHourTimeDialog> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue ?? '23:00';
    final parts = initial.split(':');
    _hour = int.tryParse(parts[0]) ?? 23;
    _minute = int.tryParse(parts[1]) ?? 0;
    if (_minute % 15 != 0) {
      _minute = (_minute ~/ 15) * 15;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('締切時刻を設定'),
      content: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _hour,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '時',
              ),
              items: List.generate(
                24,
                (index) => DropdownMenuItem<int>(
                  value: index,
                  child: Text(index.toString().padLeft(2, '0')),
                ),
              ),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _hour = value;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _minute,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '分',
              ),
              items: const [0, 15, 30, 45]
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text(value.toString().padLeft(2, '0')),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _minute = value;
                });
              },
            ),
          ),
        ],
      ),
      actions: [
        if (widget.initialValue != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('クリア'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
