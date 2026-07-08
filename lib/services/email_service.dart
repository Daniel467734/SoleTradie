import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> sendEmailViaSmtp({
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
