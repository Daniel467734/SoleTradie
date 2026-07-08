import 'package:flutter/material.dart';

/// Shows a calendar dialog that allows selecting MULTIPLE days in a single
/// session (tap as many days as you like, then confirm once) instead of
/// Flutter's built-in [showDatePicker] which only returns one date at a time.
///
/// Returns the sorted list of selected dates (date-only, time set to
/// midnight) or `null` if the user cancelled.
Future<List<DateTime>?> showMultiDatePickerDialog({
  required BuildContext context,
  List<DateTime> initialSelectedDates = const [],
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? initialDisplayedMonth,
}) {
  return showDialog<List<DateTime>>(
    context: context,
    builder: (context) => MultiDatePickerDialog(
      initialSelectedDates: initialSelectedDates,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDisplayedMonth: initialDisplayedMonth,
    ),
  );
}

class MultiDatePickerDialog extends StatefulWidget {
  final List<DateTime> initialSelectedDates;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime? initialDisplayedMonth;

  const MultiDatePickerDialog({
    super.key,
    this.initialSelectedDates = const [],
    this.firstDate,
    this.lastDate,
    this.initialDisplayedMonth,
  });

  @override
  State<MultiDatePickerDialog> createState() => _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState extends State<MultiDatePickerDialog> {
  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _monthNames = [
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
    'December'
  ];

  late DateTime _firstDate;
  late DateTime _lastDate;
  late DateTime _displayedMonth;
  late Set<DateTime> _selectedDates;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _firstDate = _dateOnly(widget.firstDate ?? DateTime(now.year - 1));
    _lastDate = _dateOnly(widget.lastDate ?? DateTime(now.year + 2));
    _selectedDates = widget.initialSelectedDates.map(_dateOnly).toSet();

    final seedMonth = widget.initialDisplayedMonth ??
        (_selectedDates.isNotEmpty ? _selectedDates.first : now);
    _displayedMonth = DateTime(seedMonth.year, seedMonth.month);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _monthIndex(DateTime d) => d.year * 12 + d.month;

  bool get _canGoPrevious => _monthIndex(_displayedMonth) > _monthIndex(_firstDate);
  bool get _canGoNext => _monthIndex(_displayedMonth) < _monthIndex(_lastDate);

  void _goToPreviousMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    });
  }

  void _toggleDate(DateTime date) {
    setState(() {
      if (!_selectedDates.remove(date)) {
        _selectedDates.add(date);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final daysInMonth = DateUtils.getDaysInMonth(_displayedMonth.year, _displayedMonth.month);
    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    // Sunday-first grid: DateTime.weekday is 1=Mon..7=Sun.
    final leadingEmptyCells = firstDayOfMonth.weekday % 7;
    final today = _dateOnly(DateTime.now());

    final sortedSelected = _selectedDates.toList()..sort((a, b) => a.compareTo(b));

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(_selectedDates.isEmpty
                ? 'Select days'
                : 'Select days (${_selectedDates.length} selected)'),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _canGoPrevious ? _goToPreviousMonth : null,
                ),
                Text(
                  '${_monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _canGoNext ? _goToNextMonth : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: _weekdayLabels
                  .map((label) => Expanded(
                        child: Center(
                          child: Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemCount: leadingEmptyCells + daysInMonth,
              itemBuilder: (context, index) {
                if (index < leadingEmptyCells) {
                  return const SizedBox.shrink();
                }
                final day = index - leadingEmptyCells + 1;
                final date = DateTime(_displayedMonth.year, _displayedMonth.month, day);
                final isSelected = _selectedDates.contains(date);
                final isOutOfRange = date.isBefore(_firstDate) || date.isAfter(_lastDate);
                final isToday = date == today;

                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: Material(
                    color: isSelected ? colorScheme.primary : Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: isOutOfRange ? null : () => _toggleDate(date),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: (isToday && !isSelected)
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: colorScheme.primary, width: 1.2),
                              )
                            : null,
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: isOutOfRange
                                ? theme.disabledColor
                                : isSelected
                                    ? colorScheme.onPrimary
                                    : null,
                            fontWeight: isSelected || isToday ? FontWeight.bold : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _toggleDate(today),
                    icon: const Icon(Icons.today, size: 18),
                    label: const Text('Today'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, const []),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: const Text('Flexible Day'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade600,
                    ),
                  ),
                  if (_selectedDates.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selectedDates.clear()),
                      child: const Text('Clear all'),
                    ),
                ],
              ),
            ),
            if (sortedSelected.isNotEmpty) ...[
              const Divider(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: sortedSelected
                        .map((date) => Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('${date.day}/${date.month}/${date.year}'),
                              onDeleted: () => _toggleDate(date),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedDates.isEmpty
              ? null
              : () => Navigator.pop(context, sortedSelected),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
