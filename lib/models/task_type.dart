enum TaskType {
  assignment('assignment', '提出物'),
  quiz('quiz', '小テスト'),
  exam('exam', '定期テスト');

  const TaskType(this.value, this.label);

  final String value;
  final String label;

  static TaskType fromValue(String value) {
    for (final taskType in TaskType.values) {
      if (taskType.value == value) {
        return taskType;
      }
    }
    return TaskType.assignment;
  }
}
