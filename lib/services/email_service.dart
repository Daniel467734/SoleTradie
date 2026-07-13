import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'demo_mode_service.dart';

const MethodChannel _backgroundTaskChannel =
    MethodChannel('com.soletradie/background_task');

const String _pendingEmailsKey = 'pending_emails_queue';

/// Sends an email via SMTP, keeping the app alive in the background (on iOS)
/// for the duration of the send, and persisting the email to a retry queue
/// beforehand so that if the app is suspended/killed mid-send, it will be
/// automatically retried the next time the app starts (see
/// [retryPendingEmails]), instead of the email being silently lost.
Future<void> sendEmailViaSmtp({
  required List<String> toEmails,
  required String subject,
  required String body,
  List<String>? attachmentPaths,
  List<String>? cc,
  List<String>? bcc,
}) async {
  if (DemoModeService.instance.isDemoMode) {
    // DEMO MODE: never send real emails or touch the retry queue. Just
    // simulate success so callers proceed exactly like a real send.
    DemoModeService.instance.fakeSendEmail(
      documentType: subject,
      recipientEmail: toEmails.isNotEmpty ? toEmails.first : 'unknown@demo',
    );
    return;
  }

  final pendingId = DateTime.now().millisecondsSinceEpoch.toString();
  await _enqueuePendingEmail(
    id: pendingId,
    toEmails: toEmails,
    subject: subject,
    body: body,
    attachmentPaths: attachmentPaths,
    cc: cc,
    bcc: bcc,
  );

  // Ask the native side (iOS) for extra background execution time so the
  // send isn't cut off immediately if the user backgrounds/switches away
  // from the app mid-send. This is a no-op on platforms without a handler
  // (e.g. Android, which uses its own process lifecycle) - failures here
  // are intentionally ignored so email sending still proceeds normally.
  try {
    await _backgroundTaskChannel.invokeMethod('beginBackgroundTask');
  } catch (_) {}

  try {
    await _sendEmailNow(
      toEmails: toEmails,
      subject: subject,
      body: body,
      attachmentPaths: attachmentPaths,
      cc: cc,
      bcc: bcc,
    );
    await _removePendingEmail(pendingId);
  } finally {
    try {
      await _backgroundTaskChannel.invokeMethod('endBackgroundTask');
    } catch (_) {}
  }
}

Future<void> _sendEmailNow({
  required List<String> toEmails,
  required String subject,
  required String body,
  List<String>? attachmentPaths,
  List<String>? cc,
  List<String>? bcc,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final smtpEmail = prefs.getString('smtp_email');
  final smtpPassword = prefs.getString('smtp_password');
  final smtpServer = prefs.getString('smtp_server');
  final smtpPort = int.tryParse(prefs.getString('smtp_port') ?? '587') ?? 587;
  final companyName = prefs.getString('company_name') ?? smtpEmail ?? 'Company';

  if (smtpEmail == null || smtpEmail.isEmpty) {
    throw Exception('SMTP email not configured');
  }
  if (smtpPassword == null || smtpPassword.isEmpty) {
    throw Exception('SMTP password not configured');
  }
  if (smtpServer == null || smtpServer.isEmpty) {
    throw Exception('SMTP server not configured');
  }

  final smtpServerConfig = SmtpServer(
    smtpServer,
    port: smtpPort,
    username: smtpEmail,
    password: smtpPassword,
    ssl: smtpPort == 465,
  );

  final message = Message()
    ..from = Address(smtpEmail, companyName)
    ..recipients.addAll(toEmails)
    ..subject = subject
    ..text = body;

  if (cc != null) {
    message.ccRecipients.addAll(cc);
  }
  if (bcc != null) {
    message.bccRecipients.addAll(bcc);
  }

  if (attachmentPaths != null) {
    for (final path in attachmentPaths) {
      final file = File(path);
      if (await file.exists()) {
        message.attachments.add(FileAttachment(file));
      }
    }
  }

  await send(message, smtpServerConfig);
}

Future<void> _enqueuePendingEmail({
  required String id,
  required List<String> toEmails,
  required String subject,
  required String body,
  List<String>? attachmentPaths,
  List<String>? cc,
  List<String>? bcc,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final queue = prefs.getStringList(_pendingEmailsKey) ?? [];
  queue.add(jsonEncode({
    'id': id,
    'toEmails': toEmails,
    'subject': subject,
    'body': body,
    'attachmentPaths': attachmentPaths ?? [],
    'cc': cc ?? [],
    'bcc': bcc ?? [],
    'queuedAt': DateTime.now().toIso8601String(),
  }));
  await prefs.setStringList(_pendingEmailsKey, queue);
}

Future<void> _removePendingEmail(String id) async {
  final prefs = await SharedPreferences.getInstance();
  final queue = prefs.getStringList(_pendingEmailsKey) ?? [];
  queue.removeWhere((entry) {
    try {
      return jsonDecode(entry)['id'] == id;
    } catch (_) {
      return false;
    }
  });
  await prefs.setStringList(_pendingEmailsKey, queue);
}

/// Retries any emails that were queued but never confirmed as sent
/// (e.g. because the app was killed by the OS mid-send while the user
/// had moved to a different screen or backgrounded the app). Call this
/// on app startup and from the periodic background task so emails
/// always eventually go out even if a send was interrupted.
Future<void> retryPendingEmails() async {
  final prefs = await SharedPreferences.getInstance();
  final queue = prefs.getStringList(_pendingEmailsKey) ?? [];
  if (queue.isEmpty) return;

  for (final entry in List<String>.from(queue)) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(entry) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }

    // Don't retry indefinitely for very old queue entries left behind by
    // a permanently misconfigured SMTP account - stop after 3 days.
    final queuedAt = DateTime.tryParse(data['queuedAt'] as String? ?? '');
    if (queuedAt != null &&
        DateTime.now().difference(queuedAt) > const Duration(days: 3)) {
      await _removePendingEmail(data['id'] as String);
      continue;
    }

    try {
      await _sendEmailNow(
        toEmails: List<String>.from(data['toEmails'] as List),
        subject: data['subject'] as String,
        body: data['body'] as String,
        attachmentPaths: List<String>.from(data['attachmentPaths'] as List),
        cc: List<String>.from(data['cc'] as List),
        bcc: List<String>.from(data['bcc'] as List),
      );
      await _removePendingEmail(data['id'] as String);
    } catch (_) {
      // Leave it in the queue - will retry again next time.
    }
  }
}
