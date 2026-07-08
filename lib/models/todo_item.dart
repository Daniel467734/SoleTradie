import 'package:intl/intl.dart';

/// Priority levels for to-do items
enum TodoPriority {
  low,
  medium,
  high;

  String get displayName {
    switch (this) {
      case TodoPriority.low:
        return 'Low';
      case TodoPriority.medium:
        return 'Medium';
      case TodoPriority.high:
        return 'High';
    }
  }

  int get sortValue {
    switch (this) {
      case TodoPriority.high:
        return 3;
      case TodoPriority.medium:
        return 2;
      case TodoPriority.low:
        return 1;
    }
  }

  static TodoPriority fromString(String? value) {
    return TodoPriority.values.firstWhere(
      (p) => p.name == value,
      orElse: () => TodoPriority.medium,
    );
  }
}

/// Represents a single item in the to-do list
class ToDoItem {
  final String id;
  final String title;
  final String? description;
  bool isCompleted;
  final DateTime createdDate;
  final String? linkedJobId; // Links to a Job for context
  final String? linkedJobTitle; // Cached job title for display
  DateTime? linkedFlexibleDayId; // Links to a flexible day job (if from scheduling)
  
  // New fields
  DateTime? dueDate;
  TodoPriority priority;
  String? category; // e.g., "Follow-up", "Invoice", "Estimate", "Admin"
  bool enableReminder;
  DateTime? reminderTime;
  Duration? estimatedTime; // Time estimate to complete
  DateTime? completedDate; // Track when item was completed
  List<String> tags; // Multiple tags for organization

  ToDoItem({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdDate,
    this.linkedJobId,
    this.linkedJobTitle,
    this.linkedFlexibleDayId,
    this.dueDate,
    this.priority = TodoPriority.medium,
    this.category,
    this.enableReminder = false,
    this.reminderTime,
    this.estimatedTime,
    this.completedDate,
    this.tags = const [],
  });

  /// Check if item is overdue
  bool get isOverdue =>
      dueDate != null && dueDate!.isBefore(DateTime.now()) && !isCompleted;

  /// Check if item is due today
  bool get isDueToday {
    if (dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return today == due;
  }

  /// Get display text for linked job
  String? getLinkedJobDisplay() {
    if (linkedJobTitle != null) {
      return linkedJobTitle;
    }
    if (linkedFlexibleDayId != null) {
      final formatter = DateFormat('EEE, MMM d');
      return 'Flexible Day - ${formatter.format(linkedFlexibleDayId!)}';
    }
    return null;
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'createdDate': createdDate.toIso8601String(),
      'linkedJobId': linkedJobId,
      'linkedJobTitle': linkedJobTitle,
      'linkedFlexibleDayId': linkedFlexibleDayId?.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'priority': priority.name,
      'category': category,
      'enableReminder': enableReminder,
      'reminderTime': reminderTime?.toIso8601String(),
      'estimatedTime': estimatedTime?.inSeconds,
      'completedDate': completedDate?.toIso8601String(),
      'tags': tags,
    };
  }

  /// Create from JSON
  factory ToDoItem.fromJson(Map<String, dynamic> json) {
    return ToDoItem(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdDate: DateTime.parse(json['createdDate'] as String),
      linkedJobId: json['linkedJobId'] as String?,
      linkedJobTitle: json['linkedJobTitle'] as String?,
      linkedFlexibleDayId: json['linkedFlexibleDayId'] != null
          ? DateTime.parse(json['linkedFlexibleDayId'] as String)
          : null,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      priority: TodoPriority.fromString(json['priority'] as String?),
      category: json['category'] as String?,
      enableReminder: json['enableReminder'] as bool? ?? false,
      reminderTime: json['reminderTime'] != null
          ? DateTime.parse(json['reminderTime'] as String)
          : null,
      estimatedTime: json['estimatedTime'] != null
          ? Duration(seconds: json['estimatedTime'] as int)
          : null,
      completedDate: json['completedDate'] != null
          ? DateTime.parse(json['completedDate'] as String)
          : null,
      tags: List<String>.from(json['tags'] as List? ?? []),
    );
  }

  /// Create a copy with modified fields
  ToDoItem copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdDate,
    String? linkedJobId,
    String? linkedJobTitle,
    DateTime? linkedFlexibleDayId,
    DateTime? dueDate,
    TodoPriority? priority,
    String? category,
    bool? enableReminder,
    DateTime? reminderTime,
    Duration? estimatedTime,
    DateTime? completedDate,
    List<String>? tags,
  }) {
    return ToDoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdDate: createdDate ?? this.createdDate,
      linkedJobId: linkedJobId ?? this.linkedJobId,
      linkedJobTitle: linkedJobTitle ?? this.linkedJobTitle,
      linkedFlexibleDayId: linkedFlexibleDayId ?? this.linkedFlexibleDayId,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      enableReminder: enableReminder ?? this.enableReminder,
      reminderTime: reminderTime ?? this.reminderTime,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      completedDate: completedDate ?? this.completedDate,
      tags: tags ?? this.tags,
    );
  }
}
