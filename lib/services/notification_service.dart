import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/job.dart';
import 'email_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case "checkOverdueInvoices":
        await NotificationService._checkOverdueInvoicesBackground();
        // Also retry any emails that were interrupted mid-send while the
        // app was backgrounded/killed, so they always eventually go out.
        try {
          await retryPendingEmails();
        } catch (_) {}
        break;
    }
    return Future.value(true);
  });
}

class NotificationService {
  static const String _overdueCheckKey = 'overdue_check_task';
  static const String _lastDailyNotificationDateKey = 'last_overdue_notification_date';

  static bool _shouldRunDailyNotification(DateTime now, String? lastRunDate) {
    if (now.hour < 9) return false;
    final todayKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return lastRunDate != todayKey;
  }

  
  /// Initialize the notification service and background tasks
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
    
    // Schedule daily background check for overdue invoices
    await Workmanager().registerPeriodicTask(
      _overdueCheckKey,
      "checkOverdueInvoices",
      frequency: const Duration(hours: 24), // Check daily
      initialDelay: const Duration(hours: 1), // First check in 1 hour
      constraints: Constraints(
        networkType: NetworkType.unmetered,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );

    await _initializePushNotifications();
  }

  // ==========================================================================
  // Push notifications (FCM) - used for the "New customer added: {name}"
  // alert when a customer submits the public customer-intake web form
  // (see functions/src/index.ts's submitCustomerForm and
  // public/new-customer.html). The Cloud Function sends the push to every
  // token registered under users/{uid}/fcmTokens/{token}.
  // ==========================================================================

  /// Requests notification permission, registers this device's FCM token
  /// against the signed-in user in Firestore, and sets up a listener so the
  /// token stays up to date if it's ever rotated/refreshed by the OS.
  static Future<void> _initializePushNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // iOS/Android 13+ require an explicit permission request.
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      await _registerCurrentToken();

      // Keep the stored token fresh if the OS rotates it.
      messaging.onTokenRefresh.listen((_) {
        _registerCurrentToken();
      });

      // Foreground messages don't show a system notification banner by
      // default - listen for them so a "customer added" push while the
      // app is open still surfaces to the user via a stored notification
      // (picked up by NotificationButton the same way overdue-invoice
      // alerts are).
      FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title;
        final body = message.notification?.body;
        if (title != null && body != null) {
          _storeGenericNotification('$title: $body');
        }
      });
    } catch (e) {
      // Push notifications are a nice-to-have - never block app startup
      // on failures here (e.g. permission denied, no Firebase project
      // configured for messaging yet).
      print('⚠️ Failed to initialize push notifications: $e');
    }
  }

  /// Registers (or re-registers) this device's current FCM token against
  /// the signed-in user's `users/{uid}/fcmTokens/{token}` document.
  static Future<void> _registerCurrentToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users/${user.uid}/fcmTokens')
          .doc(token)
          .set({
        'registeredAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.toString(),
      });
    } catch (e) {
      print('⚠️ Failed to register FCM token: $e');
    }
  }

  /// Call after sign-in completes (once FirebaseAuth.currentUser is
  /// available) to make sure this device's token is registered even if
  /// [initialize] ran before the user had signed in.
  static Future<void> registerFcmTokenForCurrentUser() => _registerCurrentToken();

  static Future<void> _storeGenericNotification(String message) async {
    final prefs = await SharedPreferences.getInstance();
    final notifications = prefs.getStringList('overdue_notifications') ?? [];
    if (!notifications.contains(message)) {
      notifications.add(message);
      await prefs.setStringList('overdue_notifications', notifications);
    }
  }
  
  /// Background task to check for overdue invoices
  static Future<void> _checkOverdueInvoicesBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final lastRunDate = prefs.getString(_lastDailyNotificationDateKey);
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (!_shouldRunDailyNotification(now, lastRunDate)) {
        return;
      }
      
      // Get stored invoice data (you may need to adapt this based on your data storage)
      final jobsJson = prefs.getStringList('cached_jobs') ?? [];
      
      for (final jobJson in jobsJson) {
        // Parse job data and check for overdue invoices
        // This is a simplified version - adapt based on your actual data structure
        try {
          final parts = jobJson.split('|');
          final jobData = <String, String>{};
          for (final part in parts) {
            final keyValue = part.split(':');
            if (keyValue.length == 2) {
              jobData[keyValue[0]] = keyValue[1];
            }
          }
          
          // Check if any invoices are 7+ days overdue
          final dueDateStr = jobData['invoice_due_date'];
          final isPaidStr = jobData['invoice_is_paid'];
          
          if (dueDateStr != null && isPaidStr == 'false') {
            final dueDate = DateTime.tryParse(dueDateStr);
            if (dueDate != null) {
              final daysPastDue = now.difference(dueDate).inDays;
              
              if (daysPastDue >= 7) {
                // Store notification for display when app opens
                await _storeOverdueNotification(
                  jobData['customer_name'] ?? 'Unknown Customer',
                  jobData['invoice_number'] ?? 'Unknown Invoice',
                  daysPastDue,
                );
              }
            }
          }
        } catch (e) {
          // Skip invalid job data
          continue;
        }
      }
    await prefs.setString(_lastDailyNotificationDateKey, todayKey);
    } catch (e) {
      // Background task failed - will retry on next scheduled run
    }
  }
  
  /// Store overdue notification to be shown when app opens
  static Future<void> _storeOverdueNotification(String customerName, String invoiceNumber, int daysPastDue) async {
    final prefs = await SharedPreferences.getInstance();
    final notifications = prefs.getStringList('overdue_notifications') ?? [];
    
    final notification = 'Invoice #$invoiceNumber for $customerName is $daysPastDue days overdue';
    
    if (!notifications.contains(notification)) {
      notifications.add(notification);
      await prefs.setStringList('overdue_notifications', notifications);
    }
  }
  
  /// Check for overdue invoices from job list (for immediate checking)
  static Future<List<Map<String, dynamic>>> checkOverdueInvoices(List<Job> jobs) async {
    final overdueInvoices = <Map<String, dynamic>>[];
    final now = DateTime.now();
    
    for (final job in jobs) {
      // Check EstimateVersion invoices
      for (final version in job.estimateVersions) {
        if (version.type == 'invoice' && !version.isPaid && version.dueDate != null) {
          final daysPastDue = now.difference(version.dueDate!).inDays;
          if (daysPastDue >= 7) {
            overdueInvoices.add({
              'job': job,
              'invoice': version,
              'daysPastDue': daysPastDue,
              'customerName': job.customerName ?? 'Unknown Customer',
              'invoiceNumber': version.invoiceNumber ?? version.id ?? 'Unknown',
            });
          }
        }
      }
      
      // Check Invoice objects
      for (final invoice in job.invoices) {
        if (!invoice.isPaid && invoice.dueDate != null) {
          final daysPastDue = now.difference(invoice.dueDate!).inDays;
          if (daysPastDue >= 7) {
            overdueInvoices.add({
              'job': job,
              'invoice': invoice,
              'daysPastDue': daysPastDue,
              'customerName': job.customerName ?? 'Unknown Customer',
              'invoiceNumber': invoice.id,
            });
          }
        }
      }
    }
    
    return overdueInvoices;
  }
  
  /// Get stored overdue notifications and clear them
  static Future<List<String>> getAndClearOverdueNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final notifications = prefs.getStringList('overdue_notifications') ?? [];
    
    if (notifications.isNotEmpty) {
      await prefs.remove('overdue_notifications');
    }
    
    return notifications;
  }
  
  /// Get stored notifications without clearing them
  static Future<List<String>> getStoredNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('overdue_notifications') ?? [];
  }
  
  /// Clear all stored notifications
  static Future<void> clearStoredNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('overdue_notifications');
  }
  
  /// Cache job data for background processing
  static Future<void> cacheJobData(List<Job> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    final jobsData = <String>[];
    
    for (final job in jobs) {
      // Cache essential invoice data for background checking
      for (final version in job.estimateVersions) {
        if (version.type == 'invoice') {
          final data = [
            'customer_name:${job.customerName ?? ""}',
            'invoice_number:${version.invoiceNumber ?? version.id ?? ""}',
            'invoice_due_date:${version.dueDate?.toIso8601String() ?? ""}',
            'invoice_is_paid:${version.isPaid}',
          ].join('|');
          jobsData.add(data);
        }
      }
      
      for (final invoice in job.invoices) {
        final data = [
          'customer_name:${job.customerName ?? ""}',
          'invoice_number:${invoice.id}',
          'invoice_due_date:${invoice.dueDate?.toIso8601String() ?? ""}',
          'invoice_is_paid:${invoice.isPaid}',
        ].join('|');
        jobsData.add(data);
      }
    }
    
    await prefs.setStringList('cached_jobs', jobsData);
  }
  
  /// Show overdue invoice notifications in the app (now stores them instead of showing SnackBars)
  static Future<void> showOverdueNotifications(BuildContext context, List<Job> jobs) async {
    final storedNotifications = await getAndClearOverdueNotifications();
    final currentOverdue = await checkOverdueInvoices(jobs);
    
    // Store notifications instead of showing SnackBars
    final allNotifications = <String>[];
    
    // Add stored notifications from background task
    allNotifications.addAll(storedNotifications);
    
    // Add current overdue notifications (for immediate checking)
    for (final overdue in currentOverdue) {
      final message = 'Invoice #${overdue['invoiceNumber']} for ${overdue['customerName']} is ${overdue['daysPastDue']} days overdue - follow up required!';
      allNotifications.add(message);
    }
    
    // Store all notifications for the notification button to display
    if (allNotifications.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('overdue_notifications', allNotifications);
    }
    
    // Cache current job data for background processing
    await cacheJobData(jobs);
  }
}
