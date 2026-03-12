import 'package:flutter/material.dart';
import 'package:kigenkanri/models/notification_rules.dart';
import 'package:kigenkanri/models/user_settings.dart';
import 'package:kigenkanri/services/notification_service.dart';

class NotificationPreferencesForm extends StatefulWidget {
  const NotificationPreferencesForm({
    super.key,
    required this.initialSettings,
    required this.onSave,
  });

  final UserSettings initialSettings;
  final Future<void> Function(UserSettings settings) onSave;

  @override
  State<NotificationPreferencesForm> createState() =>
      _NotificationPreferencesFormState();
}

class _NotificationPreferencesFormState
    extends State<NotificationPreferencesForm> {
  late bool _notificationsEnabled;
  late String _timezone;
  late List<DeadlineReminderRule> _deadlineRules;
  late List<DailySummaryRule> _dailyRules;
  late UserSettings _baselineSettings;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _resetDraft();
  }

  @override
  void didUpdateWidget(covariant NotificationPreferencesForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSettings != widget.initialSettings) {
      _resetDraft();
    }
  }

  UserSettings get _draftSettings {
    return _baselineSettings.copyWith(
      notificationsEnabled: _notificationsEnabled,
      timezone: _timezone,
      deadlineReminderRules: _deadlineRules,
      dailySummaryRules: _dailyRules,
    );
  }

  bool get _hasChanges => _draftSettings != _baselineSettings;

  void _resetDraft() {
    _baselineSettings = widget.initialSettings;
    _notificationsEnabled = widget.initialSettings.notificationsEnabled;
    _timezone = supportedTimezones.contains(widget.initialSettings.timezone)
        ? widget.initialSettings.timezone
        : UserSettings.defaultTimezone;
    _deadlineRules = [...widget.initialSettings.deadlineReminderRules];
    _dailyRules = [...widget.initialSettings.dailySummaryRules];
    _errorText = null;
    _isSaving = false;
  }

  Future<void> _save() async {
    final deadlineError = validateDeadlineReminderRules(_deadlineRules);
    if (deadlineError != null) {
      setState(() {
        _errorText = deadlineError;
      });
      return;
    }

    final dailyError = validateDailySummaryRules(_dailyRules);
    if (dailyError != null) {
      setState(() {
        _errorText = dailyError;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await widget.onSave(_draftSettings);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorText = '$error';
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _baselineSettings = _draftSettings;
      _isSaving = false;
      _errorText = null;
    });
  }

  Future<void> _showDeadlineRuleDialog({
    DeadlineReminderRule? initialRule,
  }) async {
    final rule = await showDialog<DeadlineReminderRule>(
      context: context,
      builder: (context) {
        return _DeadlineRuleDialog(
          initialRule: initialRule,
          generatedId: initialRule?.id ?? _buildRuleId('deadline'),
        );
      },
    );

    if (!mounted || rule == null) {
      return;
    }

    setState(() {
      _errorText = null;
      if (initialRule == null) {
        _deadlineRules = [..._deadlineRules, rule];
      } else {
        _deadlineRules = _deadlineRules
            .map((item) => item.id == initialRule.id ? rule : item)
            .toList();
      }
    });
  }

  Future<void> _showDailyRuleDialog({DailySummaryRule? initialRule}) async {
    final rule = await showDialog<DailySummaryRule>(
      context: context,
      builder: (context) {
        return _DailySummaryRuleDialog(
          initialRule: initialRule,
          generatedId: initialRule?.id ?? _buildRuleId('daily'),
        );
      },
    );

    if (!mounted || rule == null) {
      return;
    }

    setState(() {
      _errorText = null;
      if (initialRule == null) {
        _dailyRules = [..._dailyRules, rule];
      } else {
        _dailyRules = _dailyRules
            .map((item) => item.id == initialRule.id ? rule : item)
            .toList();
      }
    });
  }

  String _buildRuleId(String prefix) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$timestamp';
  }

  @override
  Widget build(BuildContext context) {
    final deadlineRules = [
      ..._deadlineRules,
    ]..sort((left, right) => right.offsetMinutes.compareTo(left.offsetMinutes));
    final dailyRules = [..._dailyRules]
      ..sort((left, right) => left.time.compareTo(right.time));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: _notificationsEnabled,
          title: const Text('通知を有効にする'),
          subtitle: const Text('期限前通知と定時通知をまとめて有効化します'),
          onChanged: _isSaving
              ? null
              : (value) {
                  setState(() {
                    _notificationsEnabled = value;
                    _errorText = null;
                  });
                },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _timezone,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '通知タイムゾーン',
          ),
          items: supportedTimezones
              .map(
                (timezone) => DropdownMenuItem<String>(
                  value: timezone,
                  child: Text(timezone),
                ),
              )
              .toList(),
          onChanged: _isSaving
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _timezone = value;
                    _errorText = null;
                  });
                },
        ),
        const SizedBox(height: 16),
        _NotificationRuleSection(
          title: '期限前通知',
          subtitle: '締切から逆算して通知します (${deadlineRules.length}/5)',
          addLabel: '期限前通知を追加',
          canAdd:
              deadlineRules.length < maxNotificationRulesPerType && !_isSaving,
          onAdd: () => _showDeadlineRuleDialog(),
          children: deadlineRules
              .map(
                (rule) => ListTile(
                  title: Text(formatOffsetLabel(rule.offsetMinutes)),
                  subtitle: Text(rule.enabled ? '有効' : '無効'),
                  onTap: _isSaving
                      ? null
                      : () => _showDeadlineRuleDialog(initialRule: rule),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: rule.enabled,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _deadlineRules = _deadlineRules
                                      .map(
                                        (item) => item.id == rule.id
                                            ? item.copyWith(enabled: value)
                                            : item,
                                      )
                                      .toList();
                                });
                              },
                      ),
                      IconButton(
                        onPressed: _isSaving
                            ? null
                            : () {
                                setState(() {
                                  _deadlineRules = _deadlineRules
                                      .where((item) => item.id != rule.id)
                                      .toList();
                                  _errorText = null;
                                });
                              },
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '削除',
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        _NotificationRuleSection(
          title: '定時通知',
          subtitle: '指定曜日の指定時刻に要約通知します (${dailyRules.length}/5)',
          addLabel: '定時通知を追加',
          canAdd: dailyRules.length < maxNotificationRulesPerType && !_isSaving,
          onAdd: () => _showDailyRuleDialog(),
          children: dailyRules
              .map(
                (rule) => ListTile(
                  title: Text(rule.time),
                  subtitle: Text(formatWeekdaySummary(rule.weekdays)),
                  onTap: _isSaving
                      ? null
                      : () => _showDailyRuleDialog(initialRule: rule),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: rule.enabled,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _dailyRules = _dailyRules
                                      .map(
                                        (item) => item.id == rule.id
                                            ? item.copyWith(enabled: value)
                                            : item,
                                      )
                                      .toList();
                                });
                              },
                      ),
                      IconButton(
                        onPressed: _isSaving
                            ? null
                            : () {
                                setState(() {
                                  _dailyRules = _dailyRules
                                      .where((item) => item.id != rule.id)
                                      .toList();
                                  _errorText = null;
                                });
                              },
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '削除',
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving || !_hasChanges ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('通知設定を保存'),
          ),
        ),
      ],
    );
  }
}

class _NotificationRuleSection extends StatelessWidget {
  const _NotificationRuleSection({
    required this.title,
    required this.subtitle,
    required this.addLabel,
    required this.canAdd,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String addLabel;
  final bool canAdd;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 8),
            if (children.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('まだ設定されていません'),
              )
            else
              ...children,
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: canAdd ? onAdd : null,
                icon: const Icon(Icons.add),
                label: Text(addLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineRuleDialog extends StatefulWidget {
  const _DeadlineRuleDialog({required this.generatedId, this.initialRule});

  final String generatedId;
  final DeadlineReminderRule? initialRule;

  @override
  State<_DeadlineRuleDialog> createState() => _DeadlineRuleDialogState();
}

class _DeadlineRuleDialogState extends State<_DeadlineRuleDialog> {
  late int _days;
  late int _hours;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    final offset = widget.initialRule?.offsetMinutes ?? 24 * 60;
    _days = offset ~/ (24 * 60);
    final remaining = offset % (24 * 60);
    _hours = remaining ~/ 60;
    _minutes = remaining % 60;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialRule == null ? '期限前通知を追加' : '期限前通知を編集'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _days,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '日',
                  ),
                  items: List.generate(
                    31,
                    (index) => DropdownMenuItem<int>(
                      value: index,
                      child: Text('$index'),
                    ),
                  ),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _days = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _hours,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '時間',
                  ),
                  items: List.generate(
                    24,
                    (index) => DropdownMenuItem<int>(
                      value: index,
                      child: Text('$index'),
                    ),
                  ),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _hours = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _minutes,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '分',
                  ),
                  items: const [0, 15, 30, 45]
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _minutes = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('現在の設定: ${formatOffsetLabel(_offsetMinutes)}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              DeadlineReminderRule(
                id: widget.initialRule?.id ?? widget.generatedId,
                offsetMinutes: _offsetMinutes,
                enabled: widget.initialRule?.enabled ?? true,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  int get _offsetMinutes => (_days * 24 * 60) + (_hours * 60) + _minutes;
}

class _DailySummaryRuleDialog extends StatefulWidget {
  const _DailySummaryRuleDialog({required this.generatedId, this.initialRule});

  final String generatedId;
  final DailySummaryRule? initialRule;

  @override
  State<_DailySummaryRuleDialog> createState() =>
      _DailySummaryRuleDialogState();
}

class _DailySummaryRuleDialogState extends State<_DailySummaryRuleDialog> {
  late int _hour;
  late int _minute;
  late List<int> _weekdays;

  @override
  void initState() {
    super.initState();
    final initialTime = widget.initialRule?.time ?? '07:00';
    final parts = initialTime.split(':');
    _hour = int.tryParse(parts[0]) ?? 7;
    _minute = int.tryParse(parts[1]) ?? 0;
    _weekdays = [...(widget.initialRule?.weekdays ?? allWeekdays)];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialRule == null ? '定時通知を追加' : '定時通知を編集'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 12),
          const Text('曜日'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allWeekdays
                .map(
                  (weekday) => FilterChip(
                    label: Text(weekdayLabel(weekday)),
                    selected: _weekdays.contains(weekday),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _weekdays = [..._weekdays, weekday]..sort();
                        } else {
                          _weekdays = _weekdays
                              .where((value) => value != weekday)
                              .toList();
                        }
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              DailySummaryRule(
                id: widget.initialRule?.id ?? widget.generatedId,
                time:
                    '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
                weekdays: [..._weekdays]..sort(),
                enabled: widget.initialRule?.enabled ?? true,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
