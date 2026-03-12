const Object _dueTimeSentinel = Object();

class Task {
  Task({
    required this.id,
    required this.subject,
    required this.type,
    required this.title,
    required this.dueDate,
    this.dueTime,
    required this.done,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.deletedAt,
  });

  final String id;
  final String subject;
  final String type;
  final String title;
  final String dueDate;
  final String? dueTime;
  final bool done;
  final int createdAt;
  final int updatedAt;
  final bool isDeleted;
  final int? deletedAt;

  Task copyWith({
    String? id,
    String? subject,
    String? type,
    String? title,
    String? dueDate,
    Object? dueTime = _dueTimeSentinel,
    bool? done,
    int? createdAt,
    int? updatedAt,
    bool? isDeleted,
    int? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Task(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      type: type ?? this.type,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      dueTime: identical(dueTime, _dueTimeSentinel)
          ? this.dueTime
          : dueTime as String?,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject': subject,
      'type': type,
      'title': title,
      'dueDate': dueDate,
      'dueTime': dueTime,
      'done': done,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['id'] as String?) ?? '',
      subject: (json['subject'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'assignment',
      title: (json['title'] as String?) ?? '',
      dueDate: (json['dueDate'] as String?) ?? '',
      dueTime: _normalizeDueTime(json['dueTime']),
      done: (json['done'] as bool?) ?? false,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      isDeleted: (json['isDeleted'] as bool?) ?? false,
      deletedAt: (json['deletedAt'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Task &&
        other.id == id &&
        other.subject == subject &&
        other.type == type &&
        other.title == title &&
        other.dueDate == dueDate &&
        other.dueTime == dueTime &&
        other.done == done &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.isDeleted == isDeleted &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    subject,
    type,
    title,
    dueDate,
    dueTime,
    done,
    createdAt,
    updatedAt,
    isDeleted,
    deletedAt,
  );
}

String? _normalizeDueTime(Object? value) {
  final raw = value as String?;
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
}
