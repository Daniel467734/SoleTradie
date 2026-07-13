import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/todo_item.dart';
import '../services/todo_list_service.dart';
import '../services/demo_mode_service.dart';
import '../models/job.dart' as job_model;

class ToDoListScreen extends StatefulWidget {
  final String? prefilledTitle;
  final String? linkedJobId;
  final String? linkedJobTitle;
  final DateTime? linkedFlexibleDayId;
  final List<job_model.Job>? jobs;

  const ToDoListScreen({
    super.key,
    this.prefilledTitle,
    this.linkedJobId,
    this.linkedJobTitle,
    this.linkedFlexibleDayId,
    this.jobs,
  });

  @override
  State<ToDoListScreen> createState() => _ToDoListScreenState();
}

class _ToDoListScreenState extends State<ToDoListScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  List<ToDoItem> _items = [];
  List<ToDoItem> _filteredItems = [];
  bool _showCompleted = true;
  String _filterText = '';
  bool _isLoading = true;
  List<job_model.Job> _flexibleJobs = [];
  TodoPriority? _priorityFilter;
  String? _categoryFilter;
  List<String> _availableCategories = [];
  bool _bulkSelectMode = false;
  Set<String> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.prefilledTitle ?? '');
    _descriptionController = TextEditingController();
    _loadItems();
    _loadFlexibleJobs();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await ToDoListService.getAllCategories();
    setState(() {
      _availableCategories = categories;
    });
  }

  void _loadFlexibleJobs() {
    if (widget.jobs == null) return;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    _flexibleJobs = widget.jobs!
        .where((job) {
          if (job.scheduleDates == null) return false;
          return job.scheduleDates!.any((d) {
            final startOfDate = DateTime(d.year, d.month, d.day);
            return startOfDate == startOfToday;
          });
        })
        .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await ToDoListService.getAllItems();
    setState(() {
      _items = items;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    _filteredItems = _items.where((item) {
      if (!_showCompleted && item.isCompleted) return false;
      if (_filterText.isNotEmpty &&
          !item.title.toLowerCase().contains(_filterText.toLowerCase())) {
        return false;
      }
      if (_priorityFilter != null && item.priority != _priorityFilter) {
        return false;
      }
      if (_categoryFilter != null && item.category != _categoryFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  

  Future<void> _toggleItem(ToDoItem item) async {
    await ToDoListService.toggleItem(item);
    await _loadItems();
  }

  Future<void> _deleteItem(ToDoItem item) async {
    await ToDoListService.deleteItem(item.id);
    await _loadItems();
  }

  Future<void> _editItem(ToDoItem item) async {
    _titleController.text = item.title;
    _descriptionController.text = item.description ?? '';
    late TextEditingController _categoryController;
    late TextEditingController _estimateController;
    TodoPriority _selectedPriority = item.priority;
    DateTime? _selectedDueDate = item.dueDate;
    bool _reminderEnabled = item.enableReminder;

    _categoryController = TextEditingController(text: item.category ?? '');
    _estimateController = TextEditingController(
      text: item.estimatedTime != null ? item.estimatedTime!.inMinutes.toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Description
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                // Priority
                DropdownButtonFormField<TodoPriority>(
                  value: _selectedPriority,
                  decoration: InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    isDense: true,
                  ),
                  items: TodoPriority.values.map((p) => DropdownMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _getPriorityColor(p),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(p.displayName),
                      ],
                    ),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      _selectedPriority = value ?? TodoPriority.medium;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Category
                TextField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    hintText: 'e.g., Work, Personal, Urgent',
                  ),
                ),
                const SizedBox(height: 12),
                // Due Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDueDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        _selectedDueDate = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Due Date',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      _selectedDueDate != null
                          ? '${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}'
                          : 'No due date',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Time Estimate
                TextField(
                  controller: _estimateController,
                  decoration: InputDecoration(
                    labelText: 'Estimated Time (minutes)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    suffixIcon: const Icon(Icons.timer),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                // Reminder Toggle
                CheckboxListTile(
                  title: const Text('Enable Reminder'),
                  value: _reminderEnabled,
                  onChanged: (value) {
                    setDialogState(() {
                      _reminderEnabled = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (_titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a title')),
                  );
                  return;
                }

                final estimateMinutes = int.tryParse(_estimateController.text);
                final updatedItem = item.copyWith(
                  title: _titleController.text.trim(),
                  description: _descriptionController.text.isEmpty
                      ? null
                      : _descriptionController.text.trim(),
                  priority: _selectedPriority,
                  category: _categoryController.text.isNotEmpty 
                      ? _categoryController.text 
                      : 'General',
                  dueDate: _selectedDueDate,
                  estimatedTime: estimateMinutes != null && estimateMinutes > 0
                      ? Duration(minutes: estimateMinutes)
                      : null,
                  enableReminder: _reminderEnabled,
                );

                await ToDoListService.updateItem(updatedItem);
                _titleController.clear();
                _descriptionController.clear();
                _categoryController.dispose();
                _estimateController.dispose();
                await _loadItems();

                if (mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(TodoPriority priority) {
    switch (priority) {
      case TodoPriority.high:
        return Colors.red;
      case TodoPriority.medium:
        return Colors.orange;
      case TodoPriority.low:
        return Colors.green;
    }
  }

  String _formatDueDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(date.year, date.month, date.day);
    final tomorrow = today.add(const Duration(days: 1));
    
    if (dueDay == today) {
      return 'Due Today';
    } else if (dueDay == tomorrow) {
      return 'Due Tomorrow';
    } else {
      return 'Due ${date.day}/${date.month}';
    }
  }

  // Bulk Actions Methods
  void _toggleBulkSelectMode() {
    setState(() {
      _bulkSelectMode = !_bulkSelectMode;
      if (!_bulkSelectMode) {
        _selectedItemIds.clear();
      }
    });
  }

  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  void _selectAllFiltered() {
    setState(() {
      _selectedItemIds = _filteredItems.map((item) => item.id).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
    });
  }

  Future<void> _bulkMarkComplete() async {
    for (final itemId in _selectedItemIds) {
      final item = _items.firstWhere((i) => i.id == itemId);
      await ToDoListService.toggleItem(item);
    }
    await _loadItems();
    _selectedItemIds.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked ${_selectedItemIds.length} items as complete'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _bulkDelete() async {
    final count = _selectedItemIds.length;
    for (final itemId in _selectedItemIds) {
      await ToDoListService.deleteItem(itemId);
    }
    await _loadItems();
    _selectedItemIds.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $count items'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _bulkChangePriority(TodoPriority priority) async {
    for (final itemId in _selectedItemIds) {
      final item = _items.firstWhere((i) => i.id == itemId);
      final updated = item.copyWith(priority: priority);
      await ToDoListService.updateItem(updated);
    }
    await _loadItems();
    _selectedItemIds.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Changed priority for ${_selectedItemIds.length} items'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _bulkChangeCategory(String category) async {
    for (final itemId in _selectedItemIds) {
      final item = _items.firstWhere((i) => i.id == itemId);
      final updated = item.copyWith(category: category);
      await ToDoListService.updateItem(updated);
    }
    await _loadItems();
    _selectedItemIds.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Changed category for ${_selectedItemIds.length} items'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Export Methods
  Future<void> _exportAsCSV() async {
    try {
      final csv = await ToDoListService.exportAsCSV();
      
      // Save to file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      final filePath = '${directory.path}/todo_export_$timestamp.csv';
      
      final file = File(filePath);
      await file.writeAsString(csv);

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to todo_export_$timestamp.csv'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              // Can use open_file package if available
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showBulkActionsDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bulk Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${_selectedItemIds.length} items selected',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.check_circle),
              title: const Text('Mark as Complete'),
              onTap: () {
                Navigator.pop(context);
                _bulkMarkComplete();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Items?'),
                    content: Text('Delete ${_selectedItemIds.length} items permanently?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _bulkDelete();
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.priority_high),
              title: const Text('Change Priority'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Select Priority'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: TodoPriority.values.map((p) {
                        return ListTile(
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getPriorityColor(p),
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(p.displayName),
                          onTap: () {
                            Navigator.pop(context);
                            _bulkChangePriority(p);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.label),
              title: const Text('Change Category'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Select Category'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ..._availableCategories.map((cat) {
                          return ListTile(
                            title: Text(cat),
                            onTap: () {
                              Navigator.pop(context);
                              _bulkChangeCategory(cat);
                            },
                          );
                        }).toList(),
                        ListTile(
                          title: const Text('Create New Category'),
                          onTap: () {
                            Navigator.pop(context);
                            final controller = TextEditingController();
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('New Category'),
                                content: TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(labelText: 'Category name'),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      if (controller.text.isNotEmpty) {
                                        Navigator.pop(context);
                                        _bulkChangeCategory(controller.text);
                                      }
                                    },
                                    child: const Text('Create'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Export as CSV'),
              onTap: () {
                Navigator.pop(context);
                _exportAsCSV();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final incomplete =
        _filteredItems.where((item) => !item.isCompleted).toList();
    final completed =
        _filteredItems.where((item) => item.isCompleted).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: _bulkSelectMode
            ? Text('${_selectedItemIds.length} selected')
            : Text(DemoModeService.instance.isDemoMode
                ? 'To-Do List (Demo Mode)'
                : 'To-Do List'),
        centerTitle: true,
        backgroundColor: DemoModeService.instance.isDemoMode
            ? Colors.deepPurple
            : colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        actions: [
          if (_bulkSelectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAllFiltered,
              tooltip: 'Select all',
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSelection,
              tooltip: 'Clear selection',
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showBulkActionsDialog,
              tooltip: 'Bulk actions',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleBulkSelectMode,
              tooltip: 'Exit select mode',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.check_box_outlined),
              onPressed: _toggleBulkSelectMode,
              tooltip: 'Bulk select',
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _exportAsCSV,
              tooltip: 'Export as CSV',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Flexible Jobs Section
                if (widget.jobs != null && _flexibleJobs.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: ExpansionTile(
                      title: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.amber.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Flexible Day Jobs',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade800,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_flexibleJobs.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      children: _flexibleJobs.map((job) {
                        return ListTile(
                          leading: const Icon(Icons.work_outline),
                          title: Text(
                            job.title,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            job.customerName ?? 'No customer',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          trailing: Icon(Icons.arrow_forward_ios,
                              size: 14, color: Colors.amber.shade700),
                          onTap: () {
                            // Option to add these jobs to to-do if needed
                          },
                        );
                      }).toList(),
                    ),
                  ),
                
                // Search and filter bar
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        onChanged: (value) {
                          setState(() {
                            _filterText = value;
                            _applyFilters();
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search items...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _filterText.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _filterText = '';
                                      _applyFilters();
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Priority and Category Filter Row
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<TodoPriority?>(
                              value: _priorityFilter,
                              decoration: InputDecoration(
                                labelText: 'Priority',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All Priorities'),
                                ),
                                ...TodoPriority.values.map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: _getPriorityColor(p),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(p.displayName),
                                    ],
                                  ),
                                )),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _priorityFilter = value;
                                  _applyFilters();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _categoryFilter,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All Categories'),
                                ),
                                ..._availableCategories.map((cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat),
                                )),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _categoryFilter = value;
                                  _applyFilters();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Show Completed'),
                              value: _showCompleted,
                              onChanged: (value) {
                                setState(() {
                                  _showCompleted = value ?? true;
                                  _applyFilters();
                                });
                              },
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                          Text(
                            'Total: ${_filteredItems.length}',
                            style: TextStyle(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Items list
                Expanded(
                  child: _filteredItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle,
                                  size: 48, color: colorScheme.secondary),
                              const SizedBox(height: 16),
                              Text(
                                _filterText.isNotEmpty
                                    ? 'No items match your search'
                                    : 'No items yet!\nAdd one below to get started.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.secondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: incomplete.length + (completed.isNotEmpty ? 1 + completed.length : 0),
                          itemBuilder: (context, index) {
                            if (incomplete.isNotEmpty &&
                                index < incomplete.length) {
                              final item = incomplete[index];
                              return _buildItemTile(item, colorScheme);
                            } else if (index == incomplete.length) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Divider(
                                  color: colorScheme.secondary.withOpacity(0.3),
                                  height: 1,
                                ),
                              );
                            } else {
                              final item = completed[
                                  index - incomplete.length - 1];
                              return _buildItemTile(item, colorScheme,
                                  isCompleted: true);
                            }
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  Widget _buildItemTile(ToDoItem item, ColorScheme colorScheme,
      {bool isCompleted = false}) {
    final isSelected = _selectedItemIds.contains(item.id);
    
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: isSelected ? colorScheme.primary.withOpacity(0.1) : null,
      child: InkWell(
        onLongPress: _bulkSelectMode ? null : () {
          _toggleItemSelection(item.id);
          _toggleBulkSelectMode();
        },
        child: ListTile(
          leading: _bulkSelectMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleItemSelection(item.id),
                )
              : Checkbox(
                  value: item.isCompleted,
                  onChanged: (_) => _toggleItem(item),
                ),
          title: Text(
            item.title,
            style: TextStyle(
              decoration:
                  item.isCompleted ? TextDecoration.lineThrough : null,
              color: item.isCompleted
                  ? colorScheme.secondary.withOpacity(0.5)
                  : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Description
            if (item.description != null && item.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.description!,
                style: TextStyle(
                  color: colorScheme.secondary.withOpacity(0.7),
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Priority, Category, and Due Date Row
            if (item.category != null && item.category!.isNotEmpty || item.dueDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    // Priority Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _getPriorityColor(item.priority).withOpacity(0.15),
                        border: Border.all(
                          color: _getPriorityColor(item.priority),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.priority_high, 
                            size: 12, 
                            color: _getPriorityColor(item.priority),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.priority.displayName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getPriorityColor(item.priority),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Category Tag
                    if (item.category != null && item.category!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.label, 
                              size: 12, 
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.category!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Due Date with color coding
                    if (item.dueDate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: item.isOverdue ? Colors.red.withOpacity(0.15) :
                                 item.isDueToday ? Colors.orange.withOpacity(0.15) :
                                 Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today, 
                              size: 12, 
                              color: item.isOverdue ? Colors.red :
                                     item.isDueToday ? Colors.orange :
                                     Colors.grey.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDueDate(item.dueDate),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: item.isOverdue || item.isDueToday ? FontWeight.bold : FontWeight.normal,
                                color: item.isOverdue ? Colors.red :
                                       item.isDueToday ? Colors.orange :
                                       Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Time Estimate
                    if (item.estimatedTime != null && item.estimatedTime!.inMinutes > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer, 
                              size: 12, 
                              color: Colors.purple.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${item.estimatedTime!.inMinutes} mins',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.purple.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Reminder Indicator
                    if (item.enableReminder)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_active, 
                              size: 12, 
                              color: Colors.teal.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Reminder',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.teal.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            // Linked Job Display
            if (item.getLinkedJobDisplay() != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.getLinkedJobDisplay()!,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: !_bulkSelectMode
            ? PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: const Text('Edit'),
                    onTap: () => _editItem(item),
                  ),
                  PopupMenuItem(
                    child: const Text('Delete'),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Item?'),
                          content: const Text(
                              'Are you sure you want to delete this item?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                _deleteItem(item);
                                Navigator.pop(context);
                              },
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              )
            : null,
        ),
      ),
    );
  }

  void _showAddItemDialog() {
    _titleController.clear();
    _descriptionController.clear();

    late TextEditingController _categoryController;
    late TextEditingController _estimateController;
    TodoPriority _selectedPriority = TodoPriority.medium;
    DateTime? _selectedDueDate;
    bool _reminderEnabled = false;

    _categoryController = TextEditingController();
    _estimateController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add New Item',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                // Title
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    border: OutlineInputBorder(),
                    hintText: 'What do you need to do?',
                  ),
                ),
                const SizedBox(height: 12),
                // Description
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Add more details...',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                // Priority
                DropdownButtonFormField<TodoPriority>(
                  value: _selectedPriority,
                  decoration: InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    isDense: true,
                  ),
                  items: TodoPriority.values.map((p) => DropdownMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _getPriorityColor(p),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(p.displayName),
                      ],
                    ),
                  )).toList(),
                  onChanged: (value) {
                    setModalState(() {
                      _selectedPriority = value ?? TodoPriority.medium;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Category
                TextField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    hintText: 'e.g., Work, Personal, Urgent',
                  ),
                ),
                const SizedBox(height: 12),
                // Due Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setModalState(() {
                        _selectedDueDate = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Due Date',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      _selectedDueDate != null
                          ? '${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}'
                          : 'No due date',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Time Estimate
                TextField(
                  controller: _estimateController,
                  decoration: InputDecoration(
                    labelText: 'Estimated Time (minutes)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    suffixIcon: const Icon(Icons.timer),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                // Reminder Toggle
                CheckboxListTile(
                  title: const Text('Enable Reminder'),
                  value: _reminderEnabled,
                  onChanged: (value) {
                    setModalState(() {
                      _reminderEnabled = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 16),
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        _categoryController.dispose();
                        _estimateController.dispose();
                        Navigator.pop(context);
                      },
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (_titleController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a title')),
                          );
                          return;
                        }

                        // Update _addItem to use new fields
                        _addItemWithFields(
                          priority: _selectedPriority,
                          category: _categoryController.text.isNotEmpty 
                              ? _categoryController.text 
                              : 'General',
                          dueDate: _selectedDueDate,
                          estimateMinutes: int.tryParse(_estimateController.text),
                          reminderEnabled: _reminderEnabled,
                        );

                        _categoryController.dispose();
                        _estimateController.dispose();
                        Navigator.pop(context);
                      },
                      child: const Text('Add Item'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addItemWithFields({
    required TodoPriority priority,
    required String category,
    DateTime? dueDate,
    int? estimateMinutes,
    required bool reminderEnabled,
  }) async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    await ToDoListService.addItem(
      title: _titleController.text.trim(),
      description: _descriptionController.text.isEmpty
          ? null
          : _descriptionController.text.trim(),
      linkedJobId: widget.linkedJobId,
      linkedJobTitle: widget.linkedJobTitle,
      linkedFlexibleDayId: widget.linkedFlexibleDayId,
      dueDate: dueDate,
      priority: priority,
      category: category,
      enableReminder: reminderEnabled,
      reminderTime: null,
      estimatedTime: estimateMinutes != null && estimateMinutes > 0
          ? Duration(minutes: estimateMinutes)
          : null,
      tags: [],
    );

    _titleController.clear();
    _descriptionController.clear();

    await _loadItems();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Item added to to-do list'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
