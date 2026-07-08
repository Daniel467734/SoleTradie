import 'package:flutter/material.dart';
import '../models/job.dart';
import '../models/customer.dart';
import 'job_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SchedulingScreen extends StatefulWidget {
  final List<Job> jobs;
  final List<Customer> customers;

  const SchedulingScreen({super.key, required this.jobs, required this.customers});

  @override
  State<SchedulingScreen> createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends State<SchedulingScreen> {
  DateTime selectedDate = DateTime.now();
  bool _flexibleDayJobsExpanded = false;
  bool _showWeekView = false;
  
  // Map to store custom events: date string -> list of event descriptions
  final Map<String, List<String>> customEvents = {};

  @override
  void initState() {
    super.initState();
    _loadCustomEventsFromPrefs();
  }

  void _goToPreviousDay() {
    setState(() {
      selectedDate = selectedDate.subtract(const Duration(days: 1));
    });
  }

  void _goToNextDay() {
    setState(() {
      selectedDate = selectedDate.add(const Duration(days: 1));
    });
  }

  void _goToToday() {
    setState(() {
      selectedDate = DateTime.now();
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && !DateTime(picked.year, picked.month, picked.day).isAtSameMomentAs(
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day))) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  bool _isSameDay(DateTime dateA, DateTime dateB) {
    return dateA.year == dateB.year && dateA.month == dateB.month && dateA.day == dateB.day;
  }

  List<Job> get _scheduledJobs {
    return widget.jobs
        .where((job) => _isScheduledExact(job, selectedDate))
        .toList()
      ..sort((a, b) {
        final aDate = a.dueDate!;
        final bDate = b.dueDate!;
        final dateComparison = aDate.compareTo(bDate);
        if (dateComparison != 0) return dateComparison;
        final aCreated = a.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = b.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bCreated.compareTo(aCreated);
      });
  }

  List<Job> get _flexibleJobs {
    return widget.jobs
        .where((job) => _isFlexibleOnDay(job, selectedDate) && !job.isFlexibleDayJob)
        .toList()
      ..sort((a, b) {
        final aCreated = a.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = b.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bCreated.compareTo(aCreated);
      });
  }

  List<Job> get _flexibleDayJobs {
    return widget.jobs
        .where((job) => job.isFlexibleDayJob)
        .toList()
      ..sort((a, b) {
        final aCreated = a.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = b.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bCreated.compareTo(aCreated);
      });
  }

  bool _isScheduledExact(Job job, DateTime date) {
    final dueDate = job.dueDate;
    if (dueDate != null && _isSameDay(dueDate, date) && !_isFlexibleForDay(job)) {
      return true;
    }
    return false;
  }

  bool _isFlexibleOnDay(Job job, DateTime date) {
    if (job.scheduleDates != null && job.scheduleDates!.any((d) => _isSameDay(d, date))) {
      return true;
    }
    final dueDate = job.dueDate;
    return dueDate != null && _isSameDay(dueDate, date) && _isFlexibleForDay(job);
  }

  bool _isFlexibleForDay(Job job) {
    final dueDate = job.dueDate;
    if (dueDate == null) return false;
    return dueDate.hour == 0 && dueDate.minute == 0 && dueDate.second == 0 && dueDate.millisecond == 0;
  }

  String _formatHeadlineDate(DateTime date) {
    final weekday = _weekdayName(date.weekday);
    final month = _monthName(date.month);
    return '$weekday, $month ${date.day}, ${date.year}';
  }

  String _weekdayName(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[weekday - 1];
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }

  void _openJobDetails(Job job) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailsScreen(job: job, priceBook: const []),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showJobNotesDialog(Job job) async {
    final TextEditingController notesController = TextEditingController(
      text: job.notes?.isNotEmpty == true ? job.notes!.first : '',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${job.title} - Note'),
          content: TextField(
            controller: notesController,
            decoration: InputDecoration(
              hintText: 'Add a short note...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLines: 3,
            minLines: 1,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final noteText = notesController.text.trim();
                final updatedJob = job.copyWith(
                  notes: noteText.isNotEmpty ? [noteText] : [],
                );
                final index = widget.jobs.indexWhere((existing) => existing.id == job.id);
                if (index != -1) {
                  setState(() {
                    widget.jobs[index] = updatedJob;
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    notesController.dispose();
  }

  Future<void> _openJobsScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobSelectionScheduleScreen(
          jobs: widget.jobs,
          customers: widget.customers,
          selectedDate: selectedDate,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showAddOptionsDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                'Add to ${_formatHeadlineDate(selectedDate)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.assignment),
                      title: const Text('Add Job'),
                      subtitle: const Text('Select or create a job'),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: () {
                        Navigator.pop(context);
                        _openJobsScreen();
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.event_note),
                      title: const Text('Add Custom Event'),
                      subtitle: const Text('e.g., Sarah\'s birthday, Trade breakfast'),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showAddCustomEventDialog();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddCustomEventDialog() async {
    final TextEditingController controller = TextEditingController();
    
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Custom Event'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLines: null,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _addCustomEvent(selectedDate, controller.text.trim());
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    
    controller.dispose();
  }

  void _addCustomEvent(DateTime date, String eventText) {
    final dateKey = _getDateKey(date);
    setState(() {
      if (customEvents.containsKey(dateKey)) {
        customEvents[dateKey]!.add(eventText);
      } else {
        customEvents[dateKey] = [eventText];
      }
    });
    _saveCustomEventsToPrefs();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Event added: "$eventText"'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveCustomEventsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(customEvents);
      await prefs.setString('custom_events', jsonString);
    } catch (e) {
      print('Error saving custom events: $e');
    }
  }

  Future<void> _loadCustomEventsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('custom_events');
      if (jsonString != null) {
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        setState(() {
          customEvents.clear();
          decoded.forEach((key, value) {
            customEvents[key] = List<String>.from(value as List);
          });
        });
      }
    } catch (e) {
      print('Error loading custom events: $e');
    }
  }

  void _deleteCustomEvent(DateTime date, int index) {
    final dateKey = _getDateKey(date);
    setState(() {
      if (customEvents.containsKey(dateKey) && index < customEvents[dateKey]!.length) {
        customEvents[dateKey]!.removeAt(index);
        if (customEvents[dateKey]!.isEmpty) {
          customEvents.remove(dateKey);
        }
      }
    });
    _saveCustomEventsToPrefs();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Event deleted'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<String> _getCustomEventsForDate(DateTime date) {
    return customEvents[_getDateKey(date)] ?? [];
  }

  // Get week dates (Monday to Sunday)
  List<DateTime> _getWeekDates() {
    final currentWeekday = selectedDate.weekday;
    final mondayOffset = currentWeekday - 1;
    final monday = selectedDate.subtract(Duration(days: mondayOffset));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  // Get jobs for a specific date
  List<Job> _getJobsForDate(DateTime date) {
    return widget.jobs
        .where((job) {
          final dueDate = job.dueDate;
          return dueDate != null && _isSameDay(dueDate, date);
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheduledJobs = _scheduledJobs;
    final flexibleJobs = _flexibleJobs;
    final flexibleDayJobs = _flexibleDayJobs;
    final customEventsList = _getCustomEventsForDate(selectedDate);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduling'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Go to Today',
            onPressed: _goToToday,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Select Date',
            onPressed: _selectDate,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _showWeekView = value == 'week';
              });
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 'day',
                child: Row(
                  children: [
                    Icon(Icons.calendar_view_day, size: 18, color: !_showWeekView ? colorScheme.primary : null),
                    const SizedBox(width: 8),
                    const Text('Day View'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'week',
                child: Row(
                  children: [
                    Icon(Icons.calendar_view_week, size: 18, color: _showWeekView ? colorScheme.primary : null),
                    const SizedBox(width: 8),
                    const Text('Week View'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (DragEndDetails details) {
          if (details.primaryVelocity! > 0) {
            _goToPreviousDay();
          } else if (details.primaryVelocity! < 0) {
            _goToNextDay();
          }
        },
        child: Column(
          children: [
            // Quick Stats Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: colorScheme.primary.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatChip(
                    icon: Icons.schedule,
                    label: 'Scheduled',
                    count: scheduledJobs.length,
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                  _buildStatChip(
                    icon: Icons.calendar_today,
                    label: 'Flexible',
                    count: flexibleJobs.length,
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                  _buildStatChip(
                    icon: Icons.playlist_add_check,
                    label: 'To-Do',
                    count: flexibleDayJobs.length,
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                  _buildStatChip(
                    icon: Icons.event_note,
                    label: 'Events',
                    count: customEventsList.length,
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                ],
              ),
            ),
            // Date Navigation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: colorScheme.surfaceVariant,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _goToPreviousDay,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.outline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'Selected day',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatHeadlineDate(selectedDate),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _goToNextDay,
                  ),
                ],
              ),
            ),
            // Content based on view mode
            Expanded(
              child: _showWeekView ? _buildWeekView(theme, colorScheme) : _buildDayView(theme, colorScheme),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptionsDialog,
        tooltip: 'Add job or custom event',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required int count,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDayView(ThemeData theme, ColorScheme colorScheme) {
    final scheduledJobs = _scheduledJobs;
    final flexibleJobs = _flexibleJobs;
    final flexibleDayJobs = _flexibleDayJobs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        _buildScheduledCard(scheduledJobs, theme, colorScheme),
        const SizedBox(height: 16),
        _buildFlexibleCard(flexibleJobs, theme, colorScheme),
        const SizedBox(height: 16),
        _buildFlexibleDayJobsCard(flexibleDayJobs, theme, colorScheme),
        const SizedBox(height: 16),
        _buildCustomEventsCard(theme, colorScheme),
      ],
    );
  }

  Widget _buildWeekView(ThemeData theme, ColorScheme colorScheme) {
    final weekDates = _getWeekDates();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        ...List.generate(7, (index) {
          final date = weekDates[index];
          final isToday = _isSameDay(date, DateTime.now());
          final isSelected = _isSameDay(date, selectedDate);
          final dayJobs = _getJobsForDate(date);
          final dayCustom = _getCustomEventsForDate(date);
          final hasItems = dayJobs.isNotEmpty || dayCustom.isNotEmpty;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? colorScheme.primary : colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: isToday ? colorScheme.primary.withOpacity(0.1) : null,
            ),
            child: InkWell(
              onTap: () {
                setState(() {
                  selectedDate = date;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _weekdayName(date.weekday).substring(0, 3),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${date.day}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (hasItems)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${dayJobs.length + dayCustom.length}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (hasItems) ...[
                      const SizedBox(height: 8),
                      ...dayJobs.take(2).map((job) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 6, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                job.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      )),
                      if (dayJobs.length > 2)
                        Text(
                          '+${dayJobs.length - 2} more',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildScheduledCard(List<Job> scheduledJobs, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scheduledJobs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Scheduled',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          if (scheduledJobs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                'No exact-time jobs scheduled for this day.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...List.generate(scheduledJobs.length, (index) {
              final job = scheduledJobs[index];
              final isLast = index == scheduledJobs.length - 1;
              return Column(
                children: [
                  _buildTaskRow(
                    job,
                    trailingText: _formatTime(job.dueDate!),
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 1, color: colorScheme.outline.withOpacity(0.2)),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildFlexibleCard(List<Job> flexibleJobs, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (flexibleJobs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    "Today's Flexible Jobs",
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          if (flexibleJobs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                'No flexible jobs for this day.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...List.generate(flexibleJobs.length, (index) {
              final job = flexibleJobs[index];
              final isLast = index == flexibleJobs.length - 1;
              return Column(
                children: [
                  _buildTaskRow(
                    job,
                    trailingText: null,
                    colorScheme: colorScheme,
                    theme: theme,
                    isFlexible: true,
                  ),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 1, color: colorScheme.outline.withOpacity(0.2)),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildFlexibleDayJobsCard(List<Job> flexibleDayJobs, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                _flexibleDayJobsExpanded = !_flexibleDayJobsExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.playlist_add_check, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'When You Can Jobs',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${flexibleDayJobs.length}x',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _flexibleDayJobsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_flexibleDayJobsExpanded)
            if (flexibleDayJobs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  'No daily to-do jobs.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              ...List.generate(flexibleDayJobs.length, (index) {
                final job = flexibleDayJobs[index];
                final isLast = index == flexibleDayJobs.length - 1;
                return Column(
                  children: [
                    _buildTaskRow(
                      job,
                      trailingText: null,
                      colorScheme: colorScheme,
                      theme: theme,
                      isFlexible: true,
                      isFlexibleDayJob: true,
                    ),
                    if (!isLast)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(height: 1, color: colorScheme.outline.withOpacity(0.2)),
                      ),
                  ],
                );
              }),
        ],
      ),
    );
  }

  Widget _buildCustomEventsCard(ThemeData theme, ColorScheme colorScheme) {
    final customEventsList = _getCustomEventsForDate(selectedDate);
    
    return Card(
      elevation: 0,
      color: colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customEventsList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.event_note, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Custom Events',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          if (customEventsList.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                'No custom events for this day.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...List.generate(customEventsList.length, (index) {
              final event = customEventsList[index];
              final isLast = index == customEventsList.length - 1;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.event_note,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _deleteCustomEvent(selectedDate, index),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 1, color: colorScheme.outline.withOpacity(0.2)),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTaskRow(
    Job job, {
    required String? trailingText,
    required ColorScheme colorScheme,
    required ThemeData theme,
    bool isFlexible = false,
    bool isFlexibleDayJob = false,
  }) {
    final isCompleted = _isCompletedStatus(job);
    final isArchived = job.currentStatus == JobStatus.archived;
    final isDone = isCompleted || isArchived;
    final hasNote = job.notes?.isNotEmpty == true;

    return InkWell(
      onTap: () => _openJobDetails(job),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox only for flexible jobs
            if (isFlexible)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: GestureDetector(
                  onTap: () {
                    if (!isDone) {
                      final updatedJob = job.copyWith(
                        status: JobStatus.jobComplete,
                      );
                      final index = widget.jobs.indexWhere((existing) => existing.id == job.id);
                      if (index != -1) {
                        setState(() {
                          widget.jobs[index] = updatedJob;
                        });
                      }
                    }
                  },
                  child: Icon(
                    isDone ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: isDone ? Colors.green : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isArchived ? colorScheme.outline : null,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    job.customerName?.isNotEmpty == true ? job.customerName! : 'Unknown customer',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  if (job.address != null && job.address!.isNotEmpty)
                    Text(
                      job.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  // Display note if available
                  if (hasNote)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        job.notes!.first,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.secondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (trailingText != null)
                  Text(
                    trailingText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    _scheduleSubtitle(job),
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showJobNotesDialog(job),
                  child: Icon(
                    hasNote ? Icons.note : Icons.note_outlined,
                    size: 18,
                    color: hasNote ? colorScheme.secondary : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _scheduleSubtitle(Job job) {
    final scheduleDates = job.scheduleDates ?? [];
    if (scheduleDates.length > 1) {
      final sortedDates = [...scheduleDates]..sort((a, b) => a.compareTo(b));
      final firstDate = sortedDates.first;
      final lastDate = sortedDates.last;
      return 'Scheduled ${sortedDates.length} days: ${_formatSimpleDate(firstDate)} - ${_formatSimpleDate(lastDate)}';
    }
    if (scheduleDates.length == 1) {
      return 'Scheduled for ${_formatSimpleDate(scheduleDates.first)}';
    }
    return 'Flexible job — date only';
  }

  String _formatSimpleDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isCompletedStatus(Job job) {
    return job.currentStatus == JobStatus.jobComplete ||
        job.currentStatus == JobStatus.invoiceSent ||
        job.currentStatus == JobStatus.invoicePaid;
  }
}

// Job Selection & Scheduling Screen
class JobSelectionScheduleScreen extends StatefulWidget {
  final List<Job> jobs;
  final List<Customer> customers;
  final DateTime selectedDate;

  const JobSelectionScheduleScreen({
    super.key,
    required this.jobs,
    required this.customers,
    required this.selectedDate,
  });

  @override
  State<JobSelectionScheduleScreen> createState() => _JobSelectionScheduleScreenState();
}

class _JobSelectionScheduleScreenState extends State<JobSelectionScheduleScreen> {
  late String _searchQuery;

  @override
  void initState() {
    super.initState();
    _searchQuery = '';
  }

  List<Job> get _filteredJobs {
    if (_searchQuery.isEmpty) {
      return widget.jobs;
    }
    return widget.jobs
        .where((job) =>
            job.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (job.customerName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
            (job.address?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false))
        .toList();
  }

  Future<void> _scheduleJob(Job job) async {
    // Open scheduling dialog similar to job creation scheduling
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );

    if (picked == null) return;

    // Show time picker
    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );

    if (pickedTime == null) return;

    // Create scheduled datetime
    final scheduledDateTime = DateTime(
      picked.year,
      picked.month,
      picked.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // Update the job with new schedule
    final updatedJob = job.copyWith(
      dueDate: scheduledDateTime,
      scheduleDates: [scheduledDateTime],
    );

    // Update the job in the list
    final index = widget.jobs.indexWhere((j) => j.id == job.id);
    if (index != -1) {
      widget.jobs[index] = updatedJob;
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filteredJobs = _filteredJobs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Job to Schedule'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search jobs by title, customer, or address...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: filteredJobs.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No jobs available' : 'No jobs found',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filteredJobs.length,
                    itemBuilder: (context, index) {
                      final job = filteredJobs[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(job.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                job.customerName ?? 'Unknown customer',
                                style: theme.textTheme.bodySmall,
                              ),
                              if (job.address != null && job.address!.isNotEmpty)
                                Text(
                                  job.address!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _scheduleJob(job),
                            child: const Text('Schedule'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
