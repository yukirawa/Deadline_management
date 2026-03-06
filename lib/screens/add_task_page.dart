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
  });

  final String subject;
  final String type;
  final String title;
  final String dueDate;
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

    if (!mounted) {
      return;
    }

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        _showDateError = false;
      });
    }
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
                      child: const Text('日付選択'),
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
