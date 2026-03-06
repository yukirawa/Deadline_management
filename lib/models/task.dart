class Task {
  Task({
    required this.id,
    required this.subject,
    required this.type,
    required this.title,
    required this.dueDate,
    required this.done,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String subject;
  final String type;
  final String title;
  final String dueDate;
  final bool done;
  final int createdAt;
  final int updatedAt;

  Task copyWith({
    String? id,
    String? subject,
    String? type,
    String? title,
    String? dueDate,
    bool? done,
    int? createdAt,
    int? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      type: type ?? this.type,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject': subject,
      'type': type,
      'title': title,
      'dueDate': dueDate,
      'done': done,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['id'] as String?) ?? '',
      subject: (json['subject'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'assignment',
      title: (json['title'] as String?) ?? '',
      dueDate: (json['dueDate'] as String?) ?? '',
      done: (json['done'] as bool?) ?? false,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
