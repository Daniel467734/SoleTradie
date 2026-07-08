import 'package:flutter/material.dart';
import '../services/todo_list_service.dart';

/// Dashboard widget showing to-do list statistics
class ToDoStatsWidget extends StatefulWidget {
  final VoidCallback? onTap;

  const ToDoStatsWidget({
    super.key,
    this.onTap,
  });

  @override
  State<ToDoStatsWidget> createState() => _ToDoStatsWidgetState();
}

class _ToDoStatsWidgetState extends State<ToDoStatsWidget> {
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    _statsFuture = ToDoListService.getStats();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return FutureBuilder<Map<String, dynamic>>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Card(
            color: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final stats = snapshot.data!;
        final completionRate = ((stats['completionRate'] as double) * 100).toStringAsFixed(0);
        final completedThisWeek = stats['completedThisWeek'] as int;
        final dueTodayItems = stats['dueTodayItems'] as int;
        final overdueItems = stats['overdueItems'] as int;
        final highPriorityItems = stats['highPriorityItems'] as int;

        return GestureDetector(
          onTap: widget.onTap,
          child: Card(
            color: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.assignment_turned_in, 
                               color: colorScheme.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'This Week\'s Progress',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$completionRate%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: stats['completionRate'] as double,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Stats grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      _buildStatBox(
                        'Completed',
                        completedThisWeek.toString(),
                        Icons.check_circle,
                        Colors.green,
                      ),
                      _buildStatBox(
                        'Due Today',
                        dueTodayItems.toString(),
                        Icons.calendar_today,
                        Colors.blue,
                      ),
                      _buildStatBox(
                        'Overdue',
                        overdueItems.toString(),
                        Icons.warning,
                        Colors.red,
                      ),
                      _buildStatBox(
                        'High Priority',
                        highPriorityItems.toString(),
                        Icons.priority_high,
                        Colors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
