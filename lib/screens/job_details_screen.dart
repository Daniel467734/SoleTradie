import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import 'estimate_builder_screen.dart';
import 'pricebook_extensive_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/job.dart' as job_model;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter/services.dart';
import '../services/email_service.dart';
import '../models/estimate_version.dart';
import '../models/estimate_template.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../services/sync_scheduler.dart';
import '../services/storage_strategy_service.dart';
import '../services/in_progress_build_service.dart';
import '../services/xero_invoice_repository_impl.dart';
import '../models/in_progress_build.dart';
import 'coc_form_screen.dart' as coc_form;
import 'esc_form_screen.dart' as esc_form;
import '../route_observer.dart';
import '../services/file_library_service.dart';
import 'todo_list_screen.dart';
import 'attachment_viewer_screen.dart';

final Map<String, Map<String, Offset>> certificateFieldPositions = {
  'COC': {
    'Reference': Offset(243, 45),
    'CompanyName': Offset(50, 20),
    'CompanyAddress': Offset(50, 35),
    'Address': Offset(134, 88),
    'CustomerName': Offset(134, 105),
    'Name': Offset(134, 198),
    'LicenceNumber': Offset(300, 198),
    'CompletionDate': Offset(380, 700),
    'SigningDate': Offset(290, 786),
    'Date2': Offset(290, 786),
    'Date1': Offset(380, 700),
    'Date3': Offset(454, 786),
    'Signature': Offset(350, 750),
  },
  'ESC': {
    'Reference': Offset(305, 62),
    'CompanyName': Offset(50, 20),
    'CompanyAddress': Offset(50, 35),
    'Address': Offset(150, 132),
    'CustomerName': Offset(150, 150),
    'Name': Offset(147, 175),
    'LicenceNumber': Offset(300, 175),
    'CompletionDate': Offset(150, 583),
    'SigningDate': Offset(400, 690),
    'Date1': Offset(150, 583),
    'Date2': Offset(400, 690),
    'Signature': Offset(300, 650),
  },
  'ROI': {
    'Reference': Offset(274, 80),
    'CompanyName': Offset(50, 20),
    'CompanyAddress': Offset(50, 35),
    'Address': Offset(128, 183),
    'CustomerName': Offset(128, 200),
    'Name': Offset(128, 220),
    'LicenceNumber': Offset(300, 220),
    'CompletionDate': Offset(427, 780),
    'SigningDate': Offset(427, 800),
    'Date1': Offset(427, 780),
    'Signature': Offset(300, 750),
  },
};

class JobDetailsScreen extends StatefulWidget {
  final job_model.Job job;
  final List<PriceBookItem> priceBook;

  const JobDetailsScreen(
      {super.key, required this.job, required this.priceBook});

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen> with RouteAware {
  static const String _builderNotePrefix = '[Estimate Builder Note] ';
  List<String> notes = [];
  final noteController = TextEditingController();
  List<EstimateTemplate> _templates = [];
  List<EstimateVersion> inProgressBuilds = [];
  bool _editing = false;
  late TextEditingController _titleController;
  late TextEditingController _descController;

  // Auto-save functionality
  Timer? _saveDebounce;
  BuildContext? _loadingDialogContext;

  /// Asks the user up-front what type of document a new Builder should
  /// create ("In Progress Estimate/Quote/Invoice Build"). The chosen type
  /// is passed into `EstimateBuilderScreen` as `initialBuildType`, and can
  /// still be changed later from within the builder itself.
  Future<String?> _showSelectBuildTypeDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Start Builder'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
            child: Text('What type of document is this build for?',
                style: TextStyle(color: Colors.black54)),
          ),
          const SizedBox(height: 8),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'estimate'),
            child: const Row(
              children: [
                Icon(Icons.description),
                SizedBox(width: 8),
                Text('Estimate'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'quote'),
            child: const Row(
              children: [
                Icon(Icons.request_quote),
                SizedBox(width: 8),
                Text('Quote'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'invoice'),
            child: const Row(
              children: [
                Icon(Icons.receipt_long),
                SizedBox(width: 8),
                Text('Invoice'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reads the build type ('estimate' | 'quote' | 'invoice') that was saved
  /// alongside an in-progress build's other data, defaulting to 'estimate'
  /// for older builds saved before this field existed.
  String _buildTypeOf(InProgressBuild build) {
    final saved = build.currentVersion.additionalData?['buildType'];
    return (saved is String && saved.isNotEmpty) ? saved : 'estimate';
  }

  String _buildTypeLabel(String type) {
    switch (type) {
      case 'invoice':
        return 'Invoice';
      case 'quote':
        return 'Quote';
      case 'estimate':
      default:
        return 'Estimate';
    }
  }

  IconData _buildTypeIcon(String type) {
    switch (type) {
      case 'invoice':
        return Icons.receipt_long;
      case 'quote':
        return Icons.request_quote;
      case 'estimate':
      default:
        return Icons.description;
    }
  }


  Future<EstimateTemplate?> showTemplatePickerDialog(
      BuildContext context, List<EstimateTemplate> templates) async {
    // Always include a blank template option
    final blankTemplate = EstimateTemplate(
      name: 'Blank Template',
      items: [],
      subsections: ['Labour', 'Materials'],
      type: 'build',
    );

    final buildTemplates = templates.where((t) => t.type == 'build').toList();
    final allTemplates = [blankTemplate, ...buildTemplates];
    String searchQuery = '';

    return showDialog<EstimateTemplate>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final filteredTemplates = searchQuery.trim().isEmpty
              ? allTemplates
              : allTemplates.where((template) {
                  final searchLower = searchQuery.toLowerCase();
                  return template.name.toLowerCase().contains(searchLower);
                }).toList();
          return AlertDialog(
            title: const Text('Select Template'),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Search templates',
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => searchQuery = ''),
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() => searchQuery = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredTemplates.length,
                      itemBuilder: (context, index) {
                        final template = filteredTemplates[index];
                        final isBlank = template.name == 'Blank Template';
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 0.0),
                          title: Text(template.name),
                          trailing: isBlank
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete template',
                                  onPressed: () async {
                                    final firstConfirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Template'),
                                        content: Text(
                                            'Delete the build template "${template.name}"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (firstConfirm != true) return;

                                    final secondConfirm =
                                        await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Confirm Delete'),
                                        content: Text(
                                            'Are you sure you want to permanently remove "${template.name}" from build templates? This cannot be undone.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red),
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Delete Forever'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (secondConfirm != true) return;

                                    setState(() {
                                      allTemplates.remove(template);
                                      buildTemplates.remove(template);
                                    });
                                    _templates.removeWhere((t) =>
                                        t.name == template.name &&
                                        t.type == 'build');
                                    await _saveTemplates();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Deleted build template "${template.name}".'),
                                        ),
                                      );
                                    }
                                  },
                                ),
                          onTap: () => Navigator.pop(context, template),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _templates.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('estimate_templates', jsonList);
  }

  Future<void> _loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('estimate_templates') ?? [];
    setState(() {
      _templates = jsonList
          .map((s) => EstimateTemplate.fromJson(jsonDecode(s)))
          .toList();
    });
  }

  @override
  void initState() {
    super.initState();
    notes = List<String>.from(widget.job.notes ?? []);
    _loadTemplates();
    _loadInProgressBuilds();
    _titleController = TextEditingController(text: widget.job.title);
    _descController = TextEditingController(text: widget.job.description ?? '');
    // Sync invoice data when screen loads
    widget.job.syncInvoices();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _saveDebounce?.cancel();
    _titleController.dispose();
    _descController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _reloadJob();
  }

  Future<void> _saveTitleAndDescription() async {
    setState(() {
      widget.job.title = _titleController.text;
      widget.job.description = _descController.text;
      _editing = false;
    });
    _markDirtyAndAutoSave();
    if (mounted) Navigator.pop(context, true); // Go back to jobs screen
  }

  void _loadInProgressBuilds() async {
    // Load in-progress builds from the proper service
    try {
      final builds =
          await InProgressBuildService.getBuildsForJob(widget.job.id);
      setState(() {
        // Convert InProgressBuild to EstimateVersion for compatibility
        inProgressBuilds = builds
            .map((build) => EstimateVersion(
                  id: build.id,
                  type: 'in_progress',
                  timestamp: build.lastModified,
                  items: build.currentVersion.items,
                  status: 'in_progress',
                  amount: build.currentVersion.totalAmount,
                  profit: build.currentVersion.totalProfit,
                ))
            .toList();
      });
    } catch (e) {
      setState(() {
        inProgressBuilds = [];
      });
    }
  }

  String _displayNoteText(String note) {
    if (note.startsWith(_builderNotePrefix)) {
      return note.substring(_builderNotePrefix.length);
    }
    return note;
  }

  bool _isBuilderNote(String note) => note.startsWith(_builderNotePrefix);

  Future<void> _saveJob() async {
    try {
      // Sync invoices before saving
      widget.job.syncInvoices();
      widget.job.notes = notes;

      // Save to local file for backward compatibility
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/job_${widget.job.id}.json');
      await file.writeAsString(jsonEncode(widget.job.toJson()));

      // Also update the main jobs list file so attachments and job changes persist
      await widget.job.save();

      // Save to cloud using hybrid storage system
      await FirestoreService.saveJob(widget.job);

      // Trigger sync through scheduler for optimal cloud sync
      await SyncScheduler.syncNow(DataType.jobs);

      // Keep Xero in sync: push any invoices that haven't been synced
      // yet (or re-push updates for already-synced ones). This is
      // idempotent and safe to call on every save.
      for (final invoice in widget.job.invoices) {
        unawaited(_pushXeroInvoiceForInvoice(invoice));
      }
    } catch (e) {
      // Still show success for local save
    }
  }

  /// Debounced auto-save to avoid frequent saves (30 second delay)
  void _debouncedSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 30), () {
      _saveJob();
    });
  }

  /// Pushes (creates/updates) the given invoice to Xero so a duplicate
  /// invoice exists there with matching customer, invoice number, line
  /// items and total. Safe to call repeatedly - the repository is
  /// idempotent and will update the existing Xero invoice rather than
  /// creating a new one on retries.
  Future<void> _pushXeroInvoiceForInvoice(dynamic invoice) async {
    try {
      final repository = XeroInvoiceRepositoryImpl();
      await repository.pushInvoice(
        job: widget.job,
        invoice: invoice,
        localInvoiceNumber: invoice.invoiceNumber ?? invoice.id ?? '',
      );
    } catch (e) {
      debugPrint('Xero invoice push failed: $e');
    }
  }

  /// Pushes a Payment to Xero for an invoice that was just marked paid
  /// locally, so both ledgers stay reconciled without double entry.
  Future<void> _pushXeroPaymentForInvoice(dynamic invoice) async {
    try {
      final repository = XeroInvoiceRepositoryImpl();
      // Ensure the invoice exists in Xero first (in case it was marked
      // paid before ever being pushed), then push the payment.
      await repository.pushInvoice(
        job: widget.job,
        invoice: invoice,
        localInvoiceNumber: invoice.invoiceNumber ?? invoice.id ?? '',
      );
      await repository.pushPayment(
        localInvoiceId: invoice.id,
        amountPaid: invoice.amount ?? invoice.total,
      );
    } catch (e) {
      debugPrint('Xero payment push failed: $e');
    }
  }

  /// Voids the linked Xero invoice when an invoice is voided, archived,
  /// or deleted locally, so a stale AUTHORISED invoice isn't left
  /// sitting in Xero after the local copy is gone. Safe/idempotent to
  /// call repeatedly - if there's no linked Xero invoice yet (or it's
  /// already voided) this is a no-op.
  Future<void> _pushXeroVoidForInvoice(dynamic invoice) async {
    try {
      final repository = XeroInvoiceRepositoryImpl();
      await repository.pushVoid(localInvoiceId: invoice.id);
    } catch (e) {
      debugPrint('Xero invoice void push failed: $e');
    }
  }

  /// Mark as having unsaved changes and trigger auto-save
  void _markDirtyAndAutoSave() {
    _debouncedSave();
  }

  Future<void> _reloadJob() async {
    try {
      // First try to load from Firestore (cloud) to get the latest data
      final cloudJob = await FirestoreService.getJob(widget.job.id);

      if (cloudJob != null) {
        setState(() {
          widget.job.estimateVersions = cloudJob.estimateVersions;
          widget.job.attachments = cloudJob.attachments;
          widget.job.notes = cloudJob.notes;
          // Update other relevant fields
        });
        // Also reload in-progress builds after updating job data
        _loadInProgressBuilds();
        return;
      }
    } catch (e) {
      // Handle error
    }

    // Fallback to local files - try main jobs.json first for consistency
    final dir = await getApplicationDocumentsDirectory();
    final mainJobsFile = File('${dir.path}/jobs.json');

    if (await mainJobsFile.exists()) {
      try {
        final jsonString = await mainJobsFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final jobData = jsonList.firstWhere((j) => j['id'] == widget.job.id,
            orElse: () => null);

        if (jobData != null) {
          final updatedJob = job_model.Job.fromJson(jobData);
          setState(() {
            widget.job.estimateVersions = updatedJob.estimateVersions;
            widget.job.attachments = updatedJob.attachments;
            widget.job.notes = updatedJob.notes;
            // Sync invoices to ensure consistency
            widget.job.syncInvoices();
          });
          return;
        }
      } catch (e) {}
    }

    // Final fallback to individual job file
    final jobFile = File('${dir.path}/job_${widget.job.id}.json');
    if (await jobFile.exists()) {
      final jsonString = await jobFile.readAsString();
      final updatedJob = job_model.Job.fromJson(jsonDecode(jsonString));
      setState(() {
        widget.job.estimateVersions = updatedJob.estimateVersions;
        widget.job.attachments = updatedJob.attachments;
        widget.job.notes = updatedJob.notes;
        widget.job.syncInvoices();
      });
    }

    // Always refresh in-progress builds when reloading job
    _loadInProgressBuilds();
  }

  Future<void> _emailCustomer() async {
    final initialEmail = widget.job.customerEmail?.trim() ?? '';
    final recipientController = TextEditingController();
    final selectedAttachments = await _promptEmailAttachments();
    if (selectedAttachments == null) return;

    final recipients = <String>[];
    if (initialEmail.isNotEmpty) recipients.add(initialEmail);

    final customerName = widget.job.emailCustomerName;
    final emailType = getEmailTypeFromAttachments(selectedAttachments);
    final prefill = await getPrefilledEmail(
      emailType: emailType,
      customerName: customerName,
    );
    final subjectController = TextEditingController(text: prefill['subject']);
    final bodyController = TextEditingController(text: prefill['body']);

    // Loop so that if sending fails, the user is taken straight back to this
    // same "Edit Email" dialog with their typed recipients/subject/body
    // retained (the list/controllers are declared outside the loop so they
    // survive across attempts) instead of losing their draft after a failed
    // send. The loop only exits via an explicit `return` — either because
    // the user cancelled a dialog, or because the email sent successfully.
    while (true) {
      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Edit Email'),
            content: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recipients',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (recipients.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No recipient added yet. Add one below.'),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: recipients
                          .map(
                            (address) => InputChip(
                              label: Text(address),
                              onDeleted: () {
                                setState(() {
                                  recipients.remove(address);
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            textCapitalization: TextCapitalization.none,
                            controller: recipientController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Add recipient',
                              hintText: 'email@example.com',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Add recipient',
                          onPressed: () {
                            final candidate = recipientController.text.trim();
                            if (candidate.isEmpty) return;
                            if (!recipients.contains(candidate)) {
                              setState(() {
                                recipients.add(candidate);
                              });
                            }
                            recipientController.clear();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      textCapitalization: TextCapitalization.sentences,
                      controller: subjectController,
                      decoration: const InputDecoration(labelText: 'Subject'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      textCapitalization: TextCapitalization.sentences,
                      controller: bodyController,
                      decoration: const InputDecoration(labelText: 'Body'),
                      maxLines: 10,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (recipients.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please add at least one recipient.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      );

      if (shouldSend != true) return;

      final delay = await showDelayPickerDialog(context);
      if (delay == null) return;
      if (delay > Duration.zero) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Email will be sent in ${delay.inMinutes} minutes')),
        );
        await Future.delayed(delay);
      }

      _showLoadingDialog('Sending email...');
      debugPrint('Email send: loading dialog shown, waiting before send');
      await Future.delayed(const Duration(milliseconds: 100));
      var sendSucceeded = false;
      try {
        debugPrint(
            'Email send: calling sendEmailViaSmtp to ${recipients.join(', ')}');
        await sendEmailViaSmtp(
          toEmails: recipients,
          subject: subjectController.text,
          body: bodyController.text,
          attachmentPaths: selectedAttachments,
        ).timeout(const Duration(seconds: 60));
        debugPrint('Email send: sendEmailViaSmtp completed');
        sendSucceeded = true;
        _closeLoadingDialog();

        final hasInvoiceAttachment = selectedAttachments
            .any((path) => path.toLowerCase().contains('invoice'));
        final hasEstimateAttachment = selectedAttachments
            .any((path) => path.toLowerCase().contains('estimate'));

        final selectedAttachmentPaths = selectedAttachments
            .map((path) => path.toLowerCase())
            .toSet();

        for (final inv in widget.job.invoices) {
          if (inv.filePath != null && selectedAttachmentPaths.contains(inv.filePath!.toLowerCase())) {
            inv.emailSent = true;
          }
        }
        for (final version in widget.job.estimateVersions) {
          if (version.filePath != null && selectedAttachmentPaths.contains(version.filePath!.toLowerCase())) {
            version.emailSent = true;
          }
        }

        if (hasInvoiceAttachment && hasEstimateAttachment) {
          widget.job.onEstimateAndInvoiceSent(
            'email-${DateTime.now().millisecondsSinceEpoch}-estimate',
            'email-${DateTime.now().millisecondsSinceEpoch}-invoice',
          );
        } else if (emailType == 'invoice') {
          widget.job
              .onInvoiceSent('email-${DateTime.now().millisecondsSinceEpoch}');
        } else if (emailType == 'estimate' || emailType == 'quote') {
          widget.job
              .onEstimateSent('email-${DateTime.now().millisecondsSinceEpoch}');
        }

        if (hasInvoiceAttachment && mounted) {
          final shouldComplete = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Invoice Sent'),
              content: const Text(
                  'Invoice sent successfully. Mark this job as complete?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes, complete'),
                ),
              ],
            ),
          );
          if (shouldComplete == true) {
            widget.job.onJobComplete();
            await _saveJob();
            if (mounted) setState(() {});
          }
        }

        await _saveJob();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email sent successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Email send failed: $e');
        _closeLoadingDialog();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Failed to send email: ${e.toString()}. Taking you back to the email editor — your message has been kept.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } finally {
        if (mounted) {
          debugPrint('Email send: closing loading dialog');
          _closeLoadingDialog();
          debugPrint('Email send: loading dialog closed');
        }
      }

      if (sendSucceeded) return;
      // Sending failed: if the screen is still mounted, loop back to the top
      // so the "Edit Email" dialog reopens with the same subjectController /
      // bodyController / recipients, retaining everything the user typed.
      if (!mounted) return;
    }
  }

  Future<List<String>?> _promptEmailAttachments() async {
    // Stage 1: show the job's own attachments first, selectable/deselectable.
    // From there the user can either finish with just those (or none), or
    // continue on to the File Library to add more before finishing.
    return _showJobAttachmentsPicker();
  }

  /// Stage 2 of the email-attachment flow: lets the user pick from the
  /// shared File Library (files reusable across jobs), optionally starting
  /// with a set of already-selected attachments carried over from Stage 1
  /// (the job's own attachments). Also offers a floating "+" button to add
  /// brand new files (PDF or Photo) straight into the Library, prompting
  /// for a name to save them under.
  Future<List<String>?> _showFileLibraryPicker({
    List<String>? initialSelected,
  }) async {
    final selectedAttachments = <String>{...?initialSelected};
    String searchQuery = '';

    return showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select from File Library'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            labelText: 'Search files',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () =>
                                        setState(() => searchQuery = ''),
                                  )
                                : null,
                          ),
                          onChanged: (value) =>
                              setState(() => searchQuery = value),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: FutureBuilder<List<FileLibraryItem>>(
                            future: searchQuery.trim().isEmpty
                                ? FileLibraryService.getAllItems()
                                : FileLibraryService.searchItems(searchQuery),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }

                              if (snapshot.hasError) {
                                return Center(
                                    child: Text('Error: ${snapshot.error}'));
                              }

                              final items = snapshot.data ?? [];

                              if (items.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'No files in library yet. Tap + to add one.',
                                  ),
                                );
                              }

                              return ListView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.only(bottom: 64),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  final isSelected = selectedAttachments
                                      .contains(item.filePath);

                                  return CheckboxListTile(
                                    value: isSelected,
                                    secondary:
                                        _buildAttachmentLeadingThumbnail(
                                            item.filePath),
                                    title: Text(item.name),
                                    subtitle: Text(
                                      'Used ${item.usageCount}x • ${FileLibraryService.getFileSize(item)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          selectedAttachments
                                              .add(item.filePath);
                                        } else {
                                          selectedAttachments
                                              .remove(item.filePath);
                                        }
                                      });
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: FloatingActionButton(
                        heroTag: 'fileLibraryAddFab',
                        tooltip: 'Add new file to Library',
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            allowMultiple: true,
                            type: FileType.any,
                          );
                          if (result == null || result.paths.isEmpty) return;

                          for (final path
                              in result.paths.whereType<String>()) {
                            final renamed = await _promptPhotoRename(
                              path.split('/').last,
                              title: 'Rename File',
                              label: 'File name',
                            );
                            if (renamed == null) continue;

                            final addedItem = await FileLibraryService.addFile(
                              File(path),
                              renamed,
                            );
                            if (addedItem != null) {
                              selectedAttachments.add(addedItem.filePath);
                            }
                          }

                          setState(() {});
                        },
                        child: const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, selectedAttachments.toList()),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Stage 1 of the email-attachment flow: shows the job's own attachments
  /// (photos + other files) first, selectable/deselectable. From here the
  /// user can Cancel (back to Job Details), jump to the File Library to add
  /// more (merging with whatever is selected here), or finish immediately
  /// with just the current selection (or none at all).
  Future<List<String>?> _showJobAttachmentsPicker() async {
    final currentAttachments = _getAttachmentFilePaths();
    final selectedAttachments = <String>{};

    return showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Separate images from other files
            final imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
            final images = currentAttachments
                .where((file) =>
                    imageExtensions.contains(file.split('.').last.toLowerCase()))
                .toList();
            final otherFiles = currentAttachments
                .where((file) =>
                    !imageExtensions.contains(file.split('.').last.toLowerCase()))
                .toList();
            final hasSelection = selectedAttachments.isNotEmpty;

            return AlertDialog(
              title: const Text('Select Attachments'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentAttachments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          'No attachments on this job yet. Use "Add from '
                          'Library" to attach a saved file, or continue '
                          'with no attachments.',
                        ),
                      ),
                    if (images.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Photos',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GridView.builder(
                          shrinkWrap: true,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: images.length,
                          itemBuilder: (context, index) {
                            final filePath = images[index];
                            final fileName = filePath.split('/').last;
                            final isSelected =
                                selectedAttachments.contains(filePath);

                            return GestureDetector(
                              onTap: () {
                                // If not in selection mode (dialog is for viewing), open viewer
                                // Otherwise, toggle selection
                                setState(() {
                                  if (isSelected) {
                                    selectedAttachments.remove(filePath);
                                  } else {
                                    selectedAttachments.add(filePath);
                                  }
                                });
                              },
                              onLongPress: () {
                                // Long press to open full-screen viewer
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AttachmentViewerScreen(
                                      attachmentPaths: images,
                                      initialIndex: images.indexOf(filePath),
                                    ),
                                  ),
                                );
                              },
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.blue
                                            : Colors.grey[300]!,
                                        width: isSelected ? 3 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: Image.file(
                                        File(filePath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error,
                                            stackTrace) {
                                          return Container(
                                            color: Colors.grey[300],
                                            child: const Center(
                                              child: Icon(
                                                Icons.broken_image,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      color: Colors.black54,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (otherFiles.isNotEmpty) ...[
                      if (images.isNotEmpty) const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Other Files',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: otherFiles.length,
                          itemBuilder: (context, index) {
                            final filePath = otherFiles[index];
                            final fileName = filePath.split('/').last;
                            final isSelected =
                                selectedAttachments.contains(filePath);

                            return CheckboxListTile(
                              value: isSelected,
                              secondary:
                                  _buildAttachmentLeadingThumbnail(filePath),
                              title: Text(fileName),
                              subtitle: Text(
                                filePath,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedAttachments.add(filePath);
                                  } else {
                                    selectedAttachments.remove(filePath);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    final libraryResult = await _showFileLibraryPicker(
                      initialSelected: selectedAttachments.toList(),
                    );
                    // If the library picker was itself cancelled, stay on
                    // this Stage 1 dialog with the selection unchanged.
                    if (libraryResult == null) return;
                    if (!context.mounted) return;
                    Navigator.pop(context, libraryResult);
                  },
                  child: Text(
                    hasSelection
                        ? 'Add attachments and From Library'
                        : 'Add from Library',
                  ),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, selectedAttachments.toList()),
                  child: Text(hasSelection ? 'Add attachments' : 'No attachments'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<String> _getAttachmentFilePaths() {
    final attachmentPaths = <String>{};
    attachmentPaths.addAll(widget.job.attachments ?? []);
    attachmentPaths.addAll(widget.job.invoiceVersions
        .map((invoice) => invoice.filePath)
        .whereType<String>());
    attachmentPaths.addAll(widget.job.estimates
        .map((estimate) => estimate.filePath)
        .whereType<String>());
    attachmentPaths.addAll(widget.job.estimateVersions
        .map((version) => version.filePath)
        .whereType<String>());
    return attachmentPaths.toList();
  }

  /// Builds a small leading thumbnail for an attachment list tile: an
  /// actual image preview for photos, a rendered first-page preview for
  /// PDFs (via [PdfThumbnail]), or a generic file icon for anything else.
  Widget _buildAttachmentLeadingThumbnail(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    const imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

    if (imageExtensions.contains(extension)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(filePath),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image),
        ),
      );
    }

    if (extension == 'pdf') {
      return PdfThumbnail(filePath: filePath, width: 40, height: 40);
    }

    return const Icon(Icons.attach_file);
  }

  Future<void> _capturePhoto() async {
    try {
      final pickedImage = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (pickedImage == null) return;

      final savedPath =
          await _savePickedPhotoWithRename(File(pickedImage.path));
      if (savedPath == null) return;

      setState(() {
        widget.job.attachments ??= [];
        widget.job.attachments!.add(savedPath);
      });

      await _saveJob();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture photo: $e')),
        );
      }
    }
  }

  Future<void> _pickPhotoFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
      );
      if (result == null || result.paths.isEmpty) return;

      final savedAttachments = <String>[];
      for (final path in result.paths.whereType<String>()) {
        final savedPath = await _savePickedPhotoWithRename(File(path));
        if (savedPath != null) {
          savedAttachments.add(savedPath);
        }
      }

      if (savedAttachments.isEmpty) return;

      setState(() {
        widget.job.attachments ??= [];
        widget.job.attachments!.addAll(savedAttachments);
      });

      await _saveJob();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    }
  }

  Future<String?> _savePickedPhotoWithRename(File originalFile) async {
    final extension = originalFile.path.split('.').last;
    final suggestedName =
        'photo_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final renamed = await _promptPhotoRename(suggestedName);
    if (renamed == null) return null;

    final safeName = _sanitizeFileName(renamed, extension);
    final docsDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${docsDir.path}/job_photos');
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }

    final destination =
        await _getUniqueFile(File('${photoDir.path}/$safeName'));
    final savedFile = await originalFile.copy(destination.path);
    return savedFile.path;
  }

  Future<String?> _promptPhotoRename(
    String suggestedName, {
    String title = 'Rename Photo',
    String label = 'Photo file name',
  }) async {
    final controller = TextEditingController(text: suggestedName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            textCapitalization: TextCapitalization.sentences,
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == null || result.trim().isEmpty) {
      return null;
    }

    return result.trim();
  }

  String _sanitizeFileName(String fileName, String extension) {
    var name = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (!name.toLowerCase().endsWith('.$extension'.toLowerCase())) {
      name = '$name.$extension';
    }
    return name.replaceAll(RegExp(r'\s+'), '_');
  }

  Future<File> _getUniqueFile(File file) async {
    if (!await file.exists()) {
      return file;
    }

    final directory = file.parent.path;
    final baseName = file.uri.pathSegments.last;
    final dotIndex = baseName.lastIndexOf('.');
    final nameWithoutExtension =
        dotIndex != -1 ? baseName.substring(0, dotIndex) : baseName;
    final extension = dotIndex != -1 ? baseName.substring(dotIndex) : '';

    var counter = 1;
    var candidate =
        File('$directory/${nameWithoutExtension}_$counter$extension');
    while (await candidate.exists()) {
      counter += 1;
      candidate = File('$directory/${nameWithoutExtension}_$counter$extension');
    }

    return candidate;
  }

  Future<void> _showVersionsDialog() async {
    final builds = await InProgressBuildService.getBuildsForJob(widget.job.id);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Versions'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: builds.isEmpty
              ? const Center(child: Text('No in-progress builds found.'))
              : ListView.builder(
                  itemCount: builds.length,
                  itemBuilder: (context, index) {
                    final build = builds[index];
                    return ListTile(
                      title: Text(build.name),
                      subtitle: Text(
                        'Updated: ${DateFormat('MMM dd, yyyy HH:mm').format(build.lastModified)}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteJobFiles() async {
    final filePaths = <String>{
      ...(widget.job.attachments ?? []),
      ...widget.job.estimateVersions
          .map((version) => version.filePath)
          .whereType<String>(),
      ...widget.job.invoices
          .map((invoice) => invoice.filePath)
          .whereType<String>(),
    };

    for (final path in filePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Failed to delete job-related file $path: $e');
      }
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final jobFile = File('${dir.path}/job_${widget.job.id}.json');
      if (await jobFile.exists()) {
        await jobFile.delete();
      }

      final jobsFile = File('${dir.path}/jobs.json');
      if (await jobsFile.exists()) {
        final rawJobs = await jobsFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(rawJobs);
        final remaining =
            jsonList.where((entry) => entry['id'] != widget.job.id).toList();
        await jobsFile.writeAsString(jsonEncode(remaining));
      }
    } catch (e) {
      debugPrint(
          'Failed to delete job metadata files for ${widget.job.id}: $e');
    }
  }

  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Job'),
        content: const Text('Are you sure you want to delete this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Void any Xero-synced invoices before deleting the job locally, so
    // they don't linger AUTHORISED in Xero with no corresponding job on
    // this side. Fire-and-forget per invoice - deletion should not be
    // blocked by network/Xero availability.
    for (final invoice in widget.job.invoices) {
      unawaited(_pushXeroVoidForInvoice(invoice));
    }

    try {
      await _deleteJobFiles();
      await FirestoreService.deleteJob(widget.job.id);
    } catch (_) {
      // If cloud deletion fails or is not available, continue with local deletion.
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job deleted successfully')),
      );
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _openAddressInMaps(String? address) async {
    if (address == null || address.trim().isEmpty) {
      debugPrint('Open maps called with empty address');
      return;
    }

    final trimmedAddress = address.trim();
    final containsCountry =
        RegExp(r'\b(new zealand|nz)\b', caseSensitive: false)
            .hasMatch(trimmedAddress);
    final searchAddress =
        containsCountry ? trimmedAddress : '$trimmedAddress, New Zealand';
    final encodedAddress = Uri.encodeComponent(searchAddress);
    final googleMapsUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    final geoUri = Uri.parse('geo:0,0?q=$encodedAddress');

    debugPrint('Maps debug: address="$address" searchAddress="$searchAddress"');
    debugPrint('Maps debug: googleMapsUri=$googleMapsUri');
    debugPrint('Maps debug: geoUri=$geoUri');

    bool launched = false;
    String failureDetails = '';

    Future<bool> _attemptLaunch(Uri uri, String label) async {
      try {
        final canLaunch = await canLaunchUrl(uri);
        debugPrint('Maps debug: canLaunchUrl($label)=$canLaunch');
        if (canLaunch) {
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          debugPrint(
              'Maps debug: launchUrl($label, externalApplication) returned $launched');
          if (launched) {
            return true;
          }
        }

        debugPrint(
            'Maps debug: attempting direct launch for $label even though canLaunchUrl=$canLaunch');
        launched = await launchUrl(uri);
        debugPrint('Maps debug: direct launchUrl($label) returned $launched');
        return launched;
      } catch (e, stackTrace) {
        debugPrint('Maps debug: Failed to launch $label: $e');
        debugPrint(stackTrace.toString());
        failureDetails += '$label launch error: $e\n';
        return false;
      }
    }

    launched = await _attemptLaunch(googleMapsUri, 'googleMapsUri');
    if (!launched) {
      debugPrint('Maps debug: failing over to geoUri');
      launched = await _attemptLaunch(geoUri, 'geoUri');
    }

    if (!launched) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not open maps. Please check the address and your device settings.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      debugPrint('Maps debug: failed to open maps. Details:\n$failureDetails');
    }
  }

  Future<void> _processInvoiceAction(dynamic invoice, String action) async {
    switch (action) {
      case 'pdf':
        if (invoice.filePath != null) {
          await OpenFile.open(invoice.filePath);
        }
        break;
      case 'builder':
        if (invoice.items != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EstimateBuilderScreen(
                job: widget.job,
                initialItems: invoice.items,
                initialSubsections: invoice.subsections,
                initialDepositAmount: invoice.depositAmount,
                initialDepositPercentage: invoice.depositPercentage,
                initialIsDepositPercentage: invoice.isDepositPercentage,
                initialBuildType: 'invoice',
              ),
            ),
          );
          await _reloadJob();
        }
        break;
      case 'paid':
        invoice.isPaid = true;
        await _saveJob();
        // Fire-and-forget: push a Payment to Xero so the two ledgers
        // stay reconciled. Local state has already been updated above
        // so the UI stays instant regardless of network conditions.
        unawaited(_pushXeroPaymentForInvoice(invoice));
        break;
      case 'void':
      case 'archive':
        invoice.isArchived = true;
        await _saveJob();
        // Fire-and-forget: void the linked Xero invoice too, so a
        // stale AUTHORISED invoice doesn't linger there after it's
        // been voided/archived locally.
        unawaited(_pushXeroVoidForInvoice(invoice));
        break;
      case 'due':
        final newDate = await showDatePicker(
          context: context,
          initialDate: invoice.dueDate ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (newDate != null) {
          invoice.dueDate = newDate;
          await _saveJob();
        }
        break;
    }
  }

  Future<void> _processEstimateAction(dynamic estimate, String action) async {
    switch (action) {
      case 'pdf':
        if (estimate.filePath != null) {
          await OpenFile.open(estimate.filePath);
        }
        break;
      case 'builder':
        if (estimate.items != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EstimateBuilderScreen(
                job: widget.job,
                initialItems: estimate.items,
                initialSubsections: estimate.sections,
                initialDepositAmount: estimate.depositAmount,
                initialDepositPercentage: estimate.depositPercentage,
                initialIsDepositPercentage: estimate.isDepositPercentage,
                initialBuildType: estimate.type,
              ),
            ),
          );
          await _reloadJob();
        }
        break;
      case 'void':
        estimate.isArchived = true;
        await _saveJob();
        break;
      case 'convert':
        if (estimate.items != null) {
          estimate.isConverted = true;
          await _saveJob();
          print('🔧 JobDetailsScreen convert action: estimate.id=${estimate.id} invoiceNumber=${estimate.invoiceNumber} type=${estimate.type}');
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EstimateBuilderScreen(
                job: widget.job,
                initialItems: estimate.items,
                initialSubsections: estimate.sections,
                convertToInvoice: true,
                initialSourceType: estimate.type,
                initialSourceTimestamp: estimate.timestamp,
                initialDepositAmount: estimate.depositAmount,
                initialDepositPercentage: estimate.depositPercentage,
                initialIsDepositPercentage: estimate.isDepositPercentage,
              ),
            ),
          );
          await _reloadJob();
        }
        break;
    }
  }

  Future<void> _showCertificateTypePicker() async {
    final selectedType = await showDialog<String>(
      context: context,
      builder: (context) {
        String choice = 'COC';
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Select Certificate Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: const Text('COC'),
                  value: 'COC',
                  groupValue: choice,
                  onChanged: (value) {
                    setState(() => choice = value ?? 'COC');
                  },
                ),
                RadioListTile<String>(
                  title: const Text('ESC'),
                  value: 'ESC',
                  groupValue: choice,
                  onChanged: (value) {
                    setState(() => choice = value ?? 'ESC');
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, choice),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );

    if (selectedType == null) return;

    if (selectedType == 'COC') {
      final didGenerate = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => coc_form.CocFormScreen(job: widget.job),
        ),
      );
      if (didGenerate == true) {
        await _reloadJob();
        if (mounted) setState(() {});
      }
    } else if (selectedType == 'ESC') {
      final didGenerate = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => esc_form.EscFormScreen(job: widget.job),
        ),
      );
      if (didGenerate == true) {
        await _reloadJob();
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _showLoadingDialog(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _loadingDialogContext = dialogContext;
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        );
      },
    );
    _loadingDialogContext = null;
  }

  void _closeLoadingDialog() {
    try {
      if (_loadingDialogContext != null &&
          Navigator.of(_loadingDialogContext!).canPop()) {
        Navigator.of(_loadingDialogContext!).pop();
      } else if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (_) {
      // Ignore pop failure.
    } finally {
      _loadingDialogContext = null;
    }
  }

  Future<void> _showCustomerEditorDialog() async {
    final job = widget.job;
    final nameController = TextEditingController(text: job.customerName ?? '');
    final companyController =
        TextEditingController(text: job.companyName ?? '');
    final addressController = TextEditingController(text: job.address ?? '');
    final emailController =
        TextEditingController(text: job.customerEmail ?? '');
    final bodyCorporateController =
        TextEditingController(text: job.bodyCorporateNumber ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customer Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Customer Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: companyController,
                decoration: const InputDecoration(labelText: 'Company Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                textCapitalization: TextCapitalization.characters,
                controller: bodyCorporateController,
                decoration:
                    const InputDecoration(labelText: 'Body Corporate Number'),
              ),
              const SizedBox(height: 12),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      setState(() {
        widget.job.customerName = nameController.text.trim().isEmpty
            ? null
            : nameController.text.trim();
        widget.job.companyName = companyController.text.trim().isEmpty
            ? null
            : companyController.text.trim();
        widget.job.bodyCorporateNumber =
            bodyCorporateController.text.trim().isEmpty
                ? null
                : bodyCorporateController.text.trim();
        widget.job.address = addressController.text.trim().isEmpty
            ? null
            : addressController.text.trim();
        widget.job.customerEmail = emailController.text.trim().isEmpty
            ? null
            : emailController.text.trim();
      });
      await _saveJob();
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final invoices =
        job.invoiceVersions; // Use invoiceVersions instead of invoices
    final estimates = job.estimates;
    final attachments = _getAttachmentFilePaths();

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_task),
            tooltip: 'Add to To-Do List',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToDoListScreen(
                    prefilledTitle: 'Follow up: ${job.title}',
                    linkedJobId: job.id,
                    linkedJobTitle: job.title,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.schedule),
            tooltip: 'Open schedule',
            onPressed: () => Navigator.pushNamed(context, '/scheduling'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'versions':
                  await _showVersionsDialog();
                  break;
                case 'delete':
                  await _showDeleteDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'versions',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Versions'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('Delete', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // --- JOB NAME AND DESCRIPTION SECTION ---
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _editing
                          ? TextField(
                              textCapitalization: TextCapitalization.sentences,
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Job Name',
                              ),
                            )
                          : Text(
                              job.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    IconButton(
                      icon: Icon(_editing ? Icons.close : Icons.edit),
                      tooltip: _editing ? 'Cancel' : 'Edit',
                      onPressed: () {
                        setState(() {
                          if (_editing) {
                            // Cancel editing, reset controllers
                            _titleController.text = job.title;
                            _descController.text = job.description ?? '';
                          }
                          _editing = !_editing;
                        });
                      },
                    ),
                  ],
                ),
                if (_editing)
                  TextField(
                    textCapitalization: TextCapitalization.sentences,
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Job Description (optional)',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  )
                else if ((job.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
                    child: Text(
                      job.description!,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                if (_editing)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                        onPressed: _saveTitleAndDescription,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () {
                          setState(() {
                            _editing = false;
                            _titleController.text = job.title;
                            _descController.text = job.description ?? '';
                          });
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
              ],
            ),
            // --- CUSTOMER DETAILS SECTION ---
            Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(
                    'Customer: ${job.customerName?.isNotEmpty == true ? job.customerName : (job.companyName?.isNotEmpty == true ? job.companyName : 'No customer')}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (job.companyName != null &&
                        job.companyName!.isNotEmpty &&
                        job.customerName?.isNotEmpty == true)
                      Text('Company: ${job.companyName}'),
                    if (job.bodyCorporateNumber != null &&
                        job.bodyCorporateNumber!.isNotEmpty)
                      Text('Body Corporate No: ${job.bodyCorporateNumber}'),
                    if (job.address != null && job.address!.isNotEmpty)
                      Row(
                        children: [
                          Expanded(child: Text('Address: ${job.address}')),
                          IconButton(
                            icon: const Icon(Icons.map),
                            tooltip: 'Open in Maps',
                            onPressed: () => _openAddressInMaps(job.address),
                          ),
                        ],
                      ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Customer',
                  onPressed: _showCustomerEditorDialog,
                ),
              ),
            ),

            // 2. BUILDER BUTTON
            ElevatedButton.icon(
              icon: const Icon(Icons.build),
              label: const Text('Builder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: () async {
                // Ask up-front what type of document this build is for.
                final selectedBuildType =
                    await _showSelectBuildTypeDialog(context);
                if (selectedBuildType == null) return;

                // Show template picker dialog
                final selectedTemplate =
                    await showTemplatePickerDialog(context, _templates);
                if (selectedTemplate != null) {
                  // Navigate to builder with selected template
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EstimateBuilderScreen(
                        job: widget.job,
                        initialTemplate: selectedTemplate,
                        initialBuildType: selectedBuildType,
                      ),
                    ),
                  );
                  await _reloadJob();
                  // Refresh the in-progress builds display
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 24),

            // --- In Progress Builds SECTION (styled like Invoices/Estimates) ---
            Row(
              children: [
                Text('In Progress Builds',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh builds',
                  onPressed: () => setState(() {}), // Refresh the FutureBuilder
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Debug builds',
                  onPressed: () async {
                    final builds = await InProgressBuildService.getBuildsForJob(
                        widget.job.id);
                    final allBuilds =
                        await InProgressBuildService.loadAllBuilds();
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Debug Info'),
                        content: SingleChildScrollView(
                          child: Text(
                            'Job ID: ${widget.job.id}\n'
                            'Builds for this job: ${builds.length}\n'
                            'Total builds in system: ${allBuilds.length}\n\n'
                            'Job builds:\n${builds.map((b) => '- ${b.name} (${b.versions.length} versions)').join('\n')}\n\n'
                            'All builds:\n${allBuilds.map((b) => '- Job ${b.jobId}: ${b.name}').join('\n')}',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            FutureBuilder<List<InProgressBuild>>(
              future: InProgressBuildService.getBuildsForJob(widget.job.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Error loading builds: ${snapshot.error}',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }

                final builds = snapshot.data ?? [];

                if (builds.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No in-progress builds.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return Column(
                  children: builds
                      .map((build) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: Icon(_buildTypeIcon(_buildTypeOf(build))),
                              title: Text(build.name),
                              subtitle: Text(
                                '${_buildTypeLabel(_buildTypeOf(build))} • Last modified: ${DateFormat('MMM dd, yyyy HH:mm').format(build.lastModified)}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EstimateBuilderScreen(
                                          job: widget.job,
                                          inProgressBuildId: build.id,
                                          initialItems:
                                              build.currentVersion.items,
                                          initialSubsections:
                                              build.currentVersion.subsections,
                                          initialDepositAmount: build
                                                      .currentVersion
                                                      .additionalData?[
                                                  'depositAmount'] is num
                                              ? (build.currentVersion
                                                          .additionalData![
                                                      'depositAmount'] as num)
                                                  .toDouble()
                                              : null,
                                          initialDepositPercentage: build
                                                      .currentVersion
                                                      .additionalData?[
                                                  'depositPercentage'] is num
                                              ? (build.currentVersion
                                                              .additionalData![
                                                          'depositPercentage']
                                                      as num)
                                                  .toDouble()
                                              : null,
                                          initialIsDepositPercentage: build
                                                      .currentVersion
                                                      .additionalData?[
                                                  'isDepositPercentage'] ==
                                              true,
                                          initialBuildType:
                                              _buildTypeOf(build),
                                        ),
                                      ),
                                    );
                                    await _reloadJob();
                                    setState(() {});
                                  } else if (action == 'versions') {
                                    await showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Build Versions'),
                                        content: SizedBox(
                                          width: double.maxFinite,
                                          height: 300,
                                          child: ListView.builder(
                                            itemCount: build.versions.length,
                                            itemBuilder: (context, index) {
                                              final version =
                                                  build.versions[index];
                                              final isLatest = version.id ==
                                                  build.currentVersionId;
                                              return ListTile(
                                                leading: Icon(
                                                  isLatest
                                                      ? Icons.star
                                                      : Icons.history,
                                                  color: isLatest
                                                      ? Colors.amber
                                                      : null,
                                                ),
                                                title: Text(
                                                    'Version ${version.id}'),
                                                subtitle: Text(
                                                  'Created: ${DateFormat('MMM dd, yyyy HH:mm').format(version.createdAt)}',
                                                ),
                                                trailing: isLatest
                                                    ? const Chip(
                                                        label: Text('Current'))
                                                    : null,
                                                onTap: () async {
                                                  Navigator.pop(context);
                                                  await Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          EstimateBuilderScreen(
                                                        job: widget.job,
                                                        inProgressBuildId:
                                                            build.id,
                                                        initialItems:
                                                            version.items,
                                                        initialSubsections:
                                                            version.subsections,
                                                        initialDepositAmount: version
                                                                        .additionalData?[
                                                                    'depositAmount']
                                                                is num
                                                            ? (version.additionalData![
                                                                        'depositAmount']
                                                                    as num)
                                                                .toDouble()
                                                            : null,
                                                        initialDepositPercentage:
                                                            version.additionalData?[
                                                                        'depositPercentage']
                                                                    is num
                                                                ? (version.additionalData![
                                                                            'depositPercentage']
                                                                        as num)
                                                                    .toDouble()
                                                                : null,
                                                        initialIsDepositPercentage:
                                                            version.additionalData?[
                                                                    'isDepositPercentage'] ==
                                                                true,
                                                        initialBuildType: version
                                                                        .additionalData?[
                                                                    'buildType']
                                                                is String
                                                            ? version.additionalData![
                                                                'buildType'] as String
                                                            : _buildTypeOf(build),
                                                      ),
                                                    ),
                                                  );
                                                  await _reloadJob();
                                                  setState(() {});
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    );
                                  } else if (action == 'delete') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text(
                                            'Delete in-progress build?'),
                                        content: const Text(
                                            'Are you sure you want to delete this in-progress build?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            style: TextButton.styleFrom(
                                                foregroundColor: Colors.red),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      try {
                                        await InProgressBuildService
                                            .deleteBuild(build.id);
                                        await _reloadJob();
                                        setState(() {});
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Build deleted successfully')),
                                        );
                                      } catch (e) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Failed to delete build: $e')),
                                        );
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'versions',
                                    child: Row(
                                      children: [
                                        Icon(Icons.history),
                                        SizedBox(width: 8),
                                        Text('Versions'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EstimateBuilderScreen(
                                      job: widget.job,
                                      inProgressBuildId: build.id,
                                      initialItems: build.currentVersion.items,
                                      initialSubsections:
                                          build.currentVersion.subsections,
                                      initialDepositAmount:
                                          build.currentVersion.additionalData?[
                                                  'depositAmount'] is num
                                              ? (build.currentVersion
                                                          .additionalData![
                                                      'depositAmount'] as num)
                                                  .toDouble()
                                              : null,
                                      initialDepositPercentage: build
                                                  .currentVersion
                                                  .additionalData?[
                                              'depositPercentage'] is num
                                          ? (build.currentVersion
                                                      .additionalData![
                                                  'depositPercentage'] as num)
                                              .toDouble()
                                          : null,
                                      initialIsDepositPercentage:
                                          build.currentVersion.additionalData?[
                                                  'isDepositPercentage'] ==
                                              true,
                                      initialBuildType: _buildTypeOf(build),
                                    ),
                                  ),
                                );
                                await _reloadJob();
                                setState(() {});
                              },
                            ),
                          ))
                      .toList(),
                );
              },
            ),
            const Divider(height: 32),

            // 3. INVOICES SECTION
            Text('Invoices', style: Theme.of(context).textTheme.titleLarge),
            ...invoices.map((invoice) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    title:
                        Text(invoice.invoiceNumber ?? invoice.id ?? "Invoice"),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Due: ${formatDate(invoice.dueDate)}'),
                        Text('Amount: \$${invoice.amount.toStringAsFixed(2)}'),
                        Text(
                            'Status: ${invoice.isPaid ? "Paid" : invoice.isArchived ? "Archived" : "Unpaid"}'),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        await _processInvoiceAction(invoice, action);
                      },
                      itemBuilder: (context) => [
                        if (invoice.filePath != null)
                          const PopupMenuItem(
                              value: 'pdf', child: Text('Open PDF')),
                        const PopupMenuItem(
                            value: 'builder', child: Text('Open in Builder')),
                        if (!invoice.isPaid)
                          const PopupMenuItem(
                              value: 'paid', child: Text('Mark as Paid')),
                        if (!invoice.isArchived)
                          const PopupMenuItem(
                              value: 'void', child: Text('Void Invoice')),
                        if (!invoice.isArchived)
                          const PopupMenuItem(
                              value: 'archive', child: Text('Archive Invoice')),
                        const PopupMenuItem(
                            value: 'due', child: Text('Change Due Date')),
                      ],
                    ),
                  ),
                )),
            const Divider(height: 32),

            // 4. QUOTES/ESTIMATES SECTION
            Text('Quotes / Estimates',
                style: Theme.of(context).textTheme.titleLarge),
            ...estimates.map((estimate) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    title: Text('${estimate.documentNumber ?? estimate.type}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!estimate.isConverted)
                          Text(
                            'Expires: ${formatDate(estimate.expiryDate)}',
                            style: TextStyle(
                              color: (estimate.expiryDate != null &&
                                      estimate.expiryDate!
                                          .isBefore(DateTime.now()))
                                  ? Colors.red
                                  : null,
                            ),
                          ),
                        if (estimate.isConverted)
                          const Text('Converted to Invoice',
                              style: TextStyle(color: Colors.green)),
                        if (estimate.isArchived)
                          const Text('Voided',
                              style: TextStyle(color: Colors.red)),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        await _processEstimateAction(estimate, action);
                      },
                      itemBuilder: (context) => [
                        if (estimate.filePath != null)
                          const PopupMenuItem(
                              value: 'pdf', child: Text('Open PDF')),
                        const PopupMenuItem(
                            value: 'builder', child: Text('Open in Builder')),
                        if (!estimate.isConverted)
                          const PopupMenuItem(
                              value: 'convert',
                              child: Text('Convert to Invoice')),
                        if (!estimate.isArchived)
                          PopupMenuItem(
                            value: 'void',
                            child: Text(
                                'Void ${estimate.type != null ? '${estimate.type![0].toUpperCase()}${estimate.type!.substring(1)}' : 'Document'}'),
                          ),
                      ],
                    ),
                  ),
                )),
            const Divider(height: 32),

            // 5. JOB NOTES SECTION
            Text('Job Notes', style: Theme.of(context).textTheme.titleLarge),
            Builder(builder: (context) {
              final builderNoteIndex = notes.indexWhere(_isBuilderNote);
              final builderNote = builderNoteIndex != -1
                  ? _displayNoteText(notes[builderNoteIndex])
                  : null;
              final regularNotes =
                  notes.where((note) => !_isBuilderNote(note)).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (builderNote != null) ...[
                    ListTile(
                      leading: const Icon(Icons.sticky_note_2),
                      title: const Text('General Job Notes'),
                      subtitle: Text(builderNote),
                      onTap: () async {
                        final shouldDelete = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete General Job Note?'),
                            content: Text(builderNote),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (shouldDelete == true) {
                          setState(() {
                            notes.removeAt(builderNoteIndex);
                          });
                          await _saveJob();
                        }
                      },
                    ),
                    const Divider(),
                  ],
                  ...regularNotes.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final note = entry.value;
                    return InkWell(
                      onTap: () async {
                        final shouldDelete = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Note?'),
                            content: Text(note),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (shouldDelete == true) {
                          setState(() {
                            notes.removeAt(idx);
                          });
                          await _saveJob();
                        }
                      },
                      child: ListTile(
                        leading: const Icon(Icons.note),
                        title: Text(note),
                      ),
                    );
                  }),
                ],
              );
            }),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    textCapitalization: TextCapitalization.sentences,
                    controller: noteController,
                    decoration: const InputDecoration(
                      hintText: 'Add a note...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    if (noteController.text.trim().isNotEmpty) {
                      setState(() {
                        notes.add(noteController.text.trim());
                        noteController.clear();
                      });
                      _markDirtyAndAutoSave();
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 32),

            // 6. ATTACHMENTS SECTION
            Text('Attachments', style: Theme.of(context).textTheme.titleLarge),
            ...attachments.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              return ListTile(
                leading: _buildAttachmentLeadingThumbnail(file),
                title: Text(file.split('/').last),
                onTap: () {
                  // Open in-house attachment viewer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttachmentViewerScreen(
                        attachmentPaths: attachments,
                        initialIndex: index,
                      ),
                    ),
                  );
                },
              );
            }),
            TextButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Add Attachment'),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: false,
                  type: FileType.any,
                );
                if (result != null && result.files.single.path != null) {
                  setState(() {
                    job.attachments ??= [];
                    job.attachments!.add(result.files.single.path!);
                  });
                  await _saveJob();
                }
              },
            ),
            const SizedBox(height: 20),
            Text('Photos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                    onPressed: _capturePhoto,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Upload Photo'),
                    onPressed: _pickPhotoFromGallery,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 32),

            // 7. CREATE CERTIFICATE SECTION
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Create Certificate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _showCertificateTypePicker,
            ),
            const SizedBox(height: 24),

            // 8. EMAIL CUSTOMER BUTTON AT BOTTOM
            ElevatedButton.icon(
              icon: const Icon(Icons.email, size: 28),
              label: const Text('Email Customer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _emailCustomer,
            ),

            // Extra bottom padding for better mobile accessibility
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}

Future<void> openCertificateAsset(String assetPath) async {
  // Load asset as bytes
  ByteData data = await rootBundle.load(assetPath);
  Uint8List bytes = data.buffer.asUint8List();

  // Save to a temp file
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${assetPath.split('/').last}');
  await file.writeAsBytes(bytes);

  // Open with default PDF app
  await OpenFile.open(file.path);
}

// Map your certType to asset path
String getCertificateAssetPath(String certType) {
  switch (certType) {
    case 'COC':
      return 'assets/certificates/COC EWRB NZ.pdf';
    case 'GAS_COC':
      return 'assets/certificates/GAS COC and GAS SAFTEY NZ.pdf';
    case 'ESC':
      return 'assets/certificates/ESC EWRB NZ.pdf';
    case 'ROI':
      return 'assets/certificates/ROI EWRB NZ.pdf';
    default:
      throw Exception('Unknown certificate type');
  }
}

Future<String> fillAndOpenCertificatePdf(
    String certType, Map<String, String> fields, String jobId) async {
  // 1. Load the PDF template from assets
  final assetPath = getCertificateAssetPath(certType);
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List();

  // 2. Load the PDF document
  final document = PdfDocument(inputBytes: bytes);

  // 3. Get the field positions for this certType
  final positions = certificateFieldPositions[certType] ?? {};

  // 4. Draw each field at its position
  final page = document.pages[0];
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  fields.forEach((field, value) {
    final offset = positions[field];
    if (offset != null) {
      page.graphics.drawString(
        value,
        font,
        bounds: Rect.fromLTWH(offset.dx, offset.dy, 300, 20),
      );
    }
  });

  // 5. Save the document to a persistent location and open it
  final outputDir = await getApplicationDocumentsDirectory();
  final certificateDir = Directory('${outputDir.path}/certificates');
  if (!await certificateDir.exists()) {
    await certificateDir.create(recursive: true);
  }

  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final safeCertType = certType.replaceAll(' ', '_').replaceAll('/', '_');
  final file = File(
      '${certificateDir.path}/${jobId}_${safeCertType}_certificate_$timestamp.pdf');
  await file.writeAsBytes(await document.save());
  document.dispose();

  await OpenFile.open(file.path);
  return file.path;
}

/// Detects whether an attachment path/filename looks like a certificate
/// document (COC, ESC, ROI, Gas COC) generated either via
/// [DocumentNamingService] (e.g. "COC 10 Main Road 11111111.pdf") or via
/// `fillAndOpenCertificatePdf` (e.g. "123_COC_certificate_20260704.pdf").
bool _isCertificateAttachment(String path) {
  final fileName = path.split(RegExp(r'[\\/]+')).last.toLowerCase().trim();
  if (fileName.contains('certificate')) return true;
  return fileName.startsWith('coc ') ||
      fileName.startsWith('coc_') ||
      fileName.startsWith('esc ') ||
      fileName.startsWith('esc_') ||
      fileName.startsWith('roi ') ||
      fileName.startsWith('roi_') ||
      fileName.startsWith('gas coc') ||
      fileName.startsWith('gas_coc');
}

String getEmailTypeFromAttachments(List<String> attachments) {
  final lowerPaths = attachments.map((path) => path.toLowerCase()).toList();
  final hasInvoice = lowerPaths.any((path) => path.contains('invoice'));
  final hasEstimate = lowerPaths.any((path) => path.contains('estimate'));
  final hasQuote = lowerPaths.any((path) => path.contains('quote'));
  final hasCertificate = attachments.any(_isCertificateAttachment);

  if (hasInvoice && hasCertificate) return 'invoice_certificate';
  if (hasInvoice && hasEstimate) return 'estimate';
  if (hasInvoice) return 'invoice';
  if (hasEstimate) return 'estimate';
  if (hasQuote) return 'quote';
  return 'message';
}

Future<Map<String, String>> getPrefilledEmail({
  required String emailType,
  required String customerName,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final companyName = prefs.getString('company_name') ?? '';
  final mainEmail = prefs.getString('main_email') ?? '';
  final fullName =
      '${prefs.getString('first_name') ?? ''} ${prefs.getString('last_name') ?? ''}'
          .trim();

  String template;
  switch (emailType) {
    case 'invoice':
      template = prefs.getString('invoice_message') ??
          '''Hi {customerName}

Find attached your invoice.

{reviewText}Many Thanks
{fullName}

{companyName}
{mainEmail}''';
      break;
    case 'invoice_certificate':
      template = prefs.getString('invoice_certificate_message') ??
          '''Hi {customerName}

Find attached your invoice and electrical certificate.

{reviewText}Many Thanks
{fullName}

{companyName}
{mainEmail}''';
      break;
    case 'estimate':
      template = prefs.getString('estimate_message') ??
          '''Hi {customerName}

Great to meet you and look at your project.

Find attached the estimate for the discussed work.

Many Thanks
{fullName}

{companyName}
{mainEmail}''';
      break;
    case 'quote':
      template = prefs.getString('quote_message') ??
          '''Hi {customerName}

Great to meet you and look at your project.

Find attached the quote for the discussed work.

Many Thanks
{fullName}

{companyName}
{mainEmail}''';
      break;
    default:
      template = prefs.getString('message_template') ??
          '''Hi {customerName}


Many Thanks
{fullName}

{companyName}
{mainEmail}''';
  }

  final body = template
      .replaceAll(
          '{customerName}',
          customerName.trim().isEmpty
              ? 'Customer'
              : customerName.trim().split(RegExp(r'\s+')).first)
      .replaceAll('{fullName}', fullName)
      .replaceAll('{companyName}', companyName)
      .replaceAll('{mainEmail}', mainEmail)
      .replaceAll('{reviewText}', '');

  late final String subject;
  if (emailType == 'invoice' || emailType == 'invoice_certificate') {
    subject = 'Invoice for ${customerName.isEmpty ? 'Customer' : customerName}';
  } else if (emailType == 'estimate') {
    subject =
        'Estimate for ${customerName.isEmpty ? 'Customer' : customerName}';
  } else if (emailType == 'quote') {
    subject = 'Quote for ${customerName.isEmpty ? 'Customer' : customerName}';
  } else {
    subject = 'Message for ${customerName.isEmpty ? 'Customer' : customerName}';
  }

  return {'subject': subject, 'body': body};
}

String formatDate(DateTime? date) {
  if (date == null) return 'No date';
  return DateFormat('dd/MM/yyyy').format(date);
}

Future<Duration?> showDelayPickerDialog(BuildContext context) async {
  return showDialog<Duration>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Send Email After'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Send now'),
            onTap: () => Navigator.pop(context, Duration.zero),
          ),
          ListTile(
            title: const Text('Send in 5 minutes'),
            onTap: () => Navigator.pop(context, const Duration(minutes: 5)),
          ),
          ListTile(
            title: const Text('Send in 10 minutes'),
            onTap: () => Navigator.pop(context, const Duration(minutes: 10)),
          ),
          ListTile(
            title: const Text('Send in 30 minutes'),
            onTap: () => Navigator.pop(context, const Duration(minutes: 30)),
          ),
        ],
      ),
    ),
  );
}
