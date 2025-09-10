import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../models/job.dart';
import '../screens/Invoices_Screen.dart';

class NotificationButton extends StatefulWidget {
  final List<Job> jobs;
  
  const NotificationButton({
    super.key,
    required this.jobs,
  });

  @override
  State<NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<NotificationButton> {
  List<Map<String, dynamic>> _notifications = [];
  bool _hasUnreadNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  @override
  void didUpdateWidget(NotificationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.jobs != oldWidget.jobs) {
      _loadNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final overdueInvoices = await NotificationService.checkOverdueInvoices(widget.jobs);
      final storedNotifications = await NotificationService.getStoredNotifications();
      
      final notifications = <Map<String, dynamic>>[];
      
      // Add overdue invoice notifications
      for (final overdue in overdueInvoices) {
        notifications.add({
          'id': 'overdue_${overdue['invoiceNumber']}',
          'type': 'overdue_invoice',
          'title': 'Invoice Overdue',
          'message': 'Invoice #${overdue['invoiceNumber']} for ${overdue['customerName']} is ${overdue['daysPastDue']} days overdue',
          'timestamp': DateTime.now(),
          'data': overdue,
          'severity': overdue['daysPastDue'] >= 30 ? 'high' : 'medium',
        });
      }
      
      // Add other stored notifications
      for (final notification in storedNotifications) {
        notifications.add({
          'id': 'stored_${DateTime.now().millisecondsSinceEpoch}',
          'type': 'general',
          'title': 'Notification',
          'message': notification,
          'timestamp': DateTime.now(),
          'data': null,
          'severity': 'low',
        });
      }
      
      // Sort by severity and timestamp
      notifications.sort((a, b) {
        final severityOrder = {'high': 3, 'medium': 2, 'low': 1};
        final aSeverity = severityOrder[a['severity']] ?? 1;
        final bSeverity = severityOrder[b['severity']] ?? 1;
        
        if (aSeverity != bSeverity) {
          return bSeverity.compareTo(aSeverity); // High severity first
        }
        
        return (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime); // Newest first
      });
      
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _hasUnreadNotifications = notifications.isNotEmpty;
        });
      }
    } catch (e) {
      print('Error loading notifications: $e');
    }
  }

  void _showNotificationsList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationsList(
        notifications: _notifications,
        onNotificationTap: _handleNotificationTap,
        onClearAll: _clearAllNotifications,
      ),
    );
    
    // Mark notifications as read
    setState(() {
      _hasUnreadNotifications = false;
    });
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    // Handle notification tap based on type
    if (notification['type'] == 'overdue_invoice') {
      // Navigate to invoice screen using the same method as dashboard
      _openInvoicesScreen();
    }
    
    // Close the notification list
    Navigator.of(context).pop();
  }
  
  void _openInvoicesScreen() {
    final allInvoices = <Map<String, Object?>>[];
    
    // Add invoices from EstimateVersions
    for (final job in widget.jobs) {
      for (final version in job.estimateVersions) {
        if (version.type == 'invoice') {
          allInvoices.add({'job': job, 'estimateVersion': version});
        }
      }
    }
    
    // Add invoices from Invoice objects
    for (final job in widget.jobs) {
      for (final invoice in job.invoices) {
        allInvoices.add({'job': job, 'invoice': invoice});
      }
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicesScreen(
          invoices: allInvoices, 
          priceBook: const [], // Empty price book since we don't have access to it here
        ),
      ),
    );
  }

  Future<void> _clearAllNotifications() async {
    try {
      await NotificationService.clearStoredNotifications();
      if (mounted) {
        setState(() {
          _notifications.clear();
          _hasUnreadNotifications = false;
        });
      }
    } catch (e) {
      print('Error clearing notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _showNotificationsList,
          tooltip: 'Notifications',
        ),
        if (_hasUnreadNotifications)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                _notifications.length > 9 ? '9+' : _notifications.length.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class NotificationsList extends StatelessWidget {
  final List<Map<String, dynamic>> notifications;
  final Function(Map<String, dynamic>) onNotificationTap;
  final VoidCallback onClearAll;

  const NotificationsList({
    super.key,
    required this.notifications,
    required this.onNotificationTap,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Notifications',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (notifications.isNotEmpty)
                  TextButton(
                    onPressed: onClearAll,
                    child: const Text(
                      'Clear All',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: notifications.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No notifications',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return NotificationItem(
                        notification: notification,
                        onTap: () => onNotificationTap(notification),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class NotificationItem extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;

  const NotificationItem({
    super.key,
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final severity = notification['severity'] as String;
    final timestamp = notification['timestamp'] as DateTime;
    
    Color severityColor;
    IconData severityIcon;
    
    switch (severity) {
      case 'high':
        severityColor = Colors.red;
        severityIcon = Icons.error_outline;
        break;
      case 'medium':
        severityColor = Colors.orange;
        severityIcon = Icons.warning_outlined;
        break;
      default:
        severityColor = Colors.blue;
        severityIcon = Icons.info_outline;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: severityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                severityIcon,
                color: severityColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification['title'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification['message'] as String,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }
}
