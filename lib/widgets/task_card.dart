import 'package:flutter/material.dart';
import 'package:kigenkanri/models/task.dart';
import 'package:kigenkanri/models/task_type.dart';
import 'package:kigenkanri/utils/deadline_utils.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.onDoneChanged,
    this.onEdit,
    this.onDelete,
    this.trailing,
    this.showCheckbox = true,
  });

  final Task task;
  final ValueChanged<bool>? onDoneChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget? trailing;
  final bool showCheckbox;

  @override
  Widget build(BuildContext context) {
    final daysLeft = calculateDaysLeft(task.dueDate);
    final risk = calculateRiskLevel(daysLeft);
    final badgeColor = _riskColor(risk);
    final textColor = task.done ? Colors.grey.shade600 : null;
    final titleStyle = task.done
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                riskLabel(risk),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${task.subject} ・ ${TaskType.fromValue(task.type).label}',
                    style: TextStyle(fontSize: 13, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ).merge(titleStyle),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        formatDisplayDate(task.dueDate),
                        style: TextStyle(color: textColor),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        remainingDaysLabel(daysLeft),
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ?trailing,
            if (trailing == null && showCheckbox)
              Checkbox(
                value: task.done,
                onChanged: onDoneChanged == null
                    ? null
                    : (checked) {
                        onDoneChanged!(checked ?? false);
                      },
              ),
            if (onEdit != null || onDelete != null)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit?.call();
                  }
                  if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  if (onEdit != null)
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('編集'),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('削除'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _riskColor(RiskLevel riskLevel) {
    switch (riskLevel) {
      case RiskLevel.expired:
        return Colors.grey.shade600;
      case RiskLevel.danger:
        return Colors.red.shade600;
      case RiskLevel.warning:
        return Colors.orange.shade700;
      case RiskLevel.safe:
        return Colors.green.shade600;
    }
  }
}
