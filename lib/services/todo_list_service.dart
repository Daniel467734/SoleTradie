import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/todo_item.dart';
import 'package:uuid/uuid.dart';
import 'demo_mode_service.dart';

/// Service for managing the to-do list with persistent storage
class ToDoListService {
  static const String _fileName = 'todo_list.json';
  static List<ToDoItem>? _cachedItems;

  /// Get the to-do list file
  static Future<File> _getToDoFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Load all to-do items from storage
  static Future<List<ToDoItem>> getAllItems() async {
    if (DemoModeService.instance.isDemoMode) {
      final items = List<ToDoItem>.from(DemoModeService.instance.todos);
      _sortItems(items);
      return items;
    }

    if (_cachedItems != null) {
      return _cachedItems!;
    }

    try {
      final file = await _getToDoFile();
      if (!await file.exists()) {
        _cachedItems = [];
        return [];
      }

      final contents = await file.readAsString();
      final json = jsonDecode(contents) as List<dynamic>;
      _cachedItems = json.map((item) => ToDoItem.fromJson(item as Map<String, dynamic>)).toList();
      
      // Sort intelligently: 
      // 1. Incomplete first
      // 2. Overdue items first
      // 3. Due today second
      // 4. By priority (high, medium, low)
      // 5. By due date
      // 6. By creation date (newest first)
      _sortItems(_cachedItems!);
      
      return _cachedItems!;
    } catch (e) {
      print('Error loading to-do items: $e');
      _cachedItems = [];
      return [];
    }
  }

  static void _sortItems(List<ToDoItem> items) {
    items.sort((a, b) {
        // Incomplete first
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        
        // For incomplete items, sort by urgency
        if (!a.isCompleted && !b.isCompleted) {
          // Overdue items first
          if (a.isOverdue != b.isOverdue) {
            return a.isOverdue ? -1 : 1;
          }
          
          // Due today second
          if (a.isDueToday != b.isDueToday) {
            return a.isDueToday ? -1 : 1;
          }
          
          // By priority (high first)
          if (a.priority.sortValue != b.priority.sortValue) {
            return b.priority.sortValue.compareTo(a.priority.sortValue);
          }
          
          // By due date (soonest first)
          if (a.dueDate != null && b.dueDate != null) {
            return a.dueDate!.compareTo(b.dueDate!);
          }
          if (a.dueDate != null) return -1;
          if (b.dueDate != null) return 1;
        }
        
        // Completed items by completion date (newest first)
        if (a.completedDate != null && b.completedDate != null) {
          return b.completedDate!.compareTo(a.completedDate!);
        }
        
        return b.createdDate.compareTo(a.createdDate);
      });
  }

  /// Save all items to storage
  static Future<void> _saveItems(List<ToDoItem> items) async {
    try {
      final file = await _getToDoFile();
      final json = jsonEncode(items.map((item) => item.toJson()).toList());
      await file.writeAsString(json);
      _cachedItems = items;
    } catch (e) {
      print('Error saving to-do items: $e');
    }
  }

  /// Add a new to-do item
  static Future<ToDoItem> addItem({
    required String title,
    String? description,
    String? linkedJobId,
    String? linkedJobTitle,
    DateTime? linkedFlexibleDayId,
    DateTime? dueDate,
    TodoPriority priority = TodoPriority.medium,
    String? category,
    bool enableReminder = false,
    DateTime? reminderTime,
    Duration? estimatedTime,
    List<String> tags = const [],
  }) async {
    const uuid = Uuid();
    final newItem = ToDoItem(
      id: uuid.v4(),
      title: title,
      description: description,
      isCompleted: false,
      createdDate: DateTime.now(),
      linkedJobId: linkedJobId,
      linkedJobTitle: linkedJobTitle,
      linkedFlexibleDayId: linkedFlexibleDayId,
      dueDate: dueDate,
      priority: priority,
      category: category,
      enableReminder: enableReminder,
      reminderTime: reminderTime,
      estimatedTime: estimatedTime,
      tags: tags,
    );

    if (DemoModeService.instance.isDemoMode) {
      DemoModeService.instance.todos.add(newItem);
      await DemoModeService.instance.persistCurrentSnapshot();
      return newItem;
    }

    final items = await getAllItems();
    items.add(newItem);
    await _saveItems(items);
    return newItem;
  }

  /// Update an existing to-do item
  static Future<void> updateItem(ToDoItem item) async {
    if (DemoModeService.instance.isDemoMode) {
      final todos = DemoModeService.instance.todos;
      final index = todos.indexWhere((i) => i.id == item.id);
      if (index != -1) {
        todos[index] = item;
        await DemoModeService.instance.persistCurrentSnapshot();
      }
      return;
    }

    final items = await getAllItems();
    final index = items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      items[index] = item;
      items.sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        return b.createdDate.compareTo(a.createdDate);
      });
      await _saveItems(items);
    }
  }

  /// Toggle completion status of an item
  static Future<void> toggleItem(ToDoItem item) async {
    if (DemoModeService.instance.isDemoMode) {
      await DemoModeService.instance.toggleTodo(item.id);
      return;
    }
    final updatedItem = item.copyWith(isCompleted: !item.isCompleted);
    await updateItem(updatedItem);
  }

  /// Delete a to-do item
  static Future<void> deleteItem(String itemId) async {
    if (DemoModeService.instance.isDemoMode) {
      DemoModeService.instance.todos.removeWhere((item) => item.id == itemId);
      await DemoModeService.instance.persistCurrentSnapshot();
      return;
    }
    final items = await getAllItems();
    items.removeWhere((item) => item.id == itemId);
    await _saveItems(items);
  }

  /// Get items linked to a specific job
  static Future<List<ToDoItem>> getItemsByJobId(String jobId) async {
    final items = await getAllItems();
    return items.where((item) => item.linkedJobId == jobId).toList();
  }

  /// Get flexible day items for a specific date
  static Future<List<ToDoItem>> getFlexibleDayItems(DateTime date) async {
    final items = await getAllItems();
    return items.where((item) {
      if (item.linkedFlexibleDayId == null) return false;
      final itemDate = item.linkedFlexibleDayId!;
      return itemDate.year == date.year &&
          itemDate.month == date.month &&
          itemDate.day == date.day;
    }).toList();
  }

  /// Get count of incomplete items
  static Future<int> getIncompleteCount() async {
    final items = await getAllItems();
    return items.where((item) => !item.isCompleted).length;
  }

  /// Get items by priority
  static Future<List<ToDoItem>> getItemsByPriority(TodoPriority priority, {bool incompleteOnly = true}) async {
    final items = await getAllItems();
    return items.where((item) {
      if (incompleteOnly && item.isCompleted) return false;
      return item.priority == priority;
    }).toList();
  }

  /// Get items by category
  static Future<List<ToDoItem>> getItemsByCategory(String category, {bool incompleteOnly = true}) async {
    final items = await getAllItems();
    return items.where((item) {
      if (incompleteOnly && item.isCompleted) return false;
      return item.category == category;
    }).toList();
  }

  /// Get overdue items
  static Future<List<ToDoItem>> getOverdueItems() async {
    final items = await getAllItems();
    return items.where((item) => item.isOverdue).toList();
  }

  /// Get items due today
  static Future<List<ToDoItem>> getDueTodayItems() async {
    final items = await getAllItems();
    return items.where((item) => item.isDueToday && !item.isCompleted).toList();
  }

  /// Get items due this week
  static Future<List<ToDoItem>> getDueThisWeekItems() async {
    final items = await getAllItems();
    final now = DateTime.now();
    final weekFromNow = now.add(const Duration(days: 7));
    return items.where((item) {
      if (item.dueDate == null || item.isCompleted) return false;
      return item.dueDate!.isAfter(now) && item.dueDate!.isBefore(weekFromNow);
    }).toList();
  }

  /// Get stats for dashboard widget
  static Future<Map<String, dynamic>> getStats() async {
    final items = await getAllItems();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = today.subtract(const Duration(days: 7));

    final completed = items.where((item) => item.isCompleted).toList();
    final completedThisWeek = completed.where((item) {
      final date = item.completedDate ?? item.createdDate;
      return date.isAfter(weekAgo);
    }).toList();

    final overdue = items.where((item) => item.isOverdue).toList();
    final dueToday = items.where((item) => item.isDueToday && !item.isCompleted).toList();
    final highPriority = items.where((item) => item.priority == TodoPriority.high && !item.isCompleted).toList();

    return {
      'totalItems': items.length,
      'completedItems': completed.length,
      'incompleteItems': items.where((item) => !item.isCompleted).length,
      'completedThisWeek': completedThisWeek.length,
      'overdueItems': overdue.length,
      'dueTodayItems': dueToday.length,
      'highPriorityItems': highPriority.length,
      'completionRate': items.isEmpty ? 0.0 : (completed.length / items.length),
    };
  }

  /// Get all unique categories
  static Future<List<String>> getAllCategories() async {
    final items = await getAllItems();
    final categories = <String>{};
    for (final item in items) {
      if (item.category != null) {
        categories.add(item.category!);
      }
    }
    return categories.toList()..sort();
  }

  /// Export items as CSV string
  static Future<String> exportAsCSV() async {
    final items = await getAllItems();
    final buffer = StringBuffer();
    buffer.writeln('Title,Description,Priority,Category,Due Date,Estimated Time,Status,Created Date');
    
    for (final item in items) {
      final dueDate = item.dueDate?.toIso8601String() ?? '';
      final estimatedTime = item.estimatedTime?.inMinutes ?? '';
      final status = item.isCompleted ? 'Completed' : 'Incomplete';
      
      buffer.writeln(
        '"${item.title}",'
        '"${item.description ?? ''}",'
        '${item.priority.displayName},'
        '"${item.category ?? ''}",'
        '$dueDate,'
        '$estimatedTime,'
        '$status,'
        '${item.createdDate.toIso8601String()}'
      );
    }
    
    return buffer.toString();
  }

  /// Clear cache (useful when switching users or refreshing)
  static void clearCache() {
    _cachedItems = null;
  }
}
