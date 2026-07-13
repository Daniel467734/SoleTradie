import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/job.dart';
import '../models/estimate_version.dart';
import '../models/invoice.dart';
import '../services/email_service.dart';
import '../services/firebase_integration_service.dart';
import 'pricebook_extensive_screen.dart' show PriceBookItem;
import 'estimate_builder_screen.dart';
import 'job_details_screen.dart';
import '../route_observer.dart';

enum InvoiceStatus { all, due, overdue, paid, archived }

class InvoicesScreen extends StatefulWidget {
  final List<Map<String, dynamic>>
      invoices; // Each: {'job': Job, 'invoice': Invoice} or {'job': Job, 'estimateVersion': EstimateVersion}
  final List<PriceBookItem> priceBook; // Add priceBook for JobDetailsScreen

  const InvoicesScreen(
      {super.key, required this.invoices, this.priceBook = const []});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> with RouteAware {
  String _searchQuery = '';
  InvoiceStatus _selectedStatus = InvoiceStatus.due;
  String _sortBy = 'date';
  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _lastFollowUpSentDates = {};

  // Internal, refreshable copy of the invoices list. Seeded from
  // `widget.invoices` so something shows immediately, then replaced with
  // freshly-loaded data from disk so the screen always reflects the latest
  // jobs/invoices, even if they changed while this screen was open.
  late List<Map<String, dynamic>> _invoices;

  @override
  void initState() {
    super.initState();
    _invoices = List<Map<String, dynamic>>.from(widget.invoices);
    _loadSentFollowUps();
    _reloadInvoicesFromDisk();
    // Also fetch directly from Firestore ourselves. widget.invoices is just
    // a snapshot taken at the moment this screen was pushed, and
    // _reloadInvoicesFromDisk() relies on dart:io/path_provider which is
    // unsupported (and silently no-ops) on Flutter web. Without this, the
    // screen could get stuck showing an empty/stale list forever if the
    // cloud sync in main.dart hadn't finished by the time this screen was
    // pushed - this pushed route is never rebuilt when main.dart's own
    // state updates later.
    _refreshInvoicesFromCloud();
  }

  /// Builds the flattened invoices list (mirrors the logic in
  /// `_reloadInvoicesFromDisk`) from an arbitrary list of jobs.
  List<Map<String, dynamic>> _buildInvoicesFromJobs(List<Job> allJobs) {
    final refreshedInvoices = <Map<String, dynamic>>[];

    for (final job in allJobs) {
      job.syncStatusFromDocuments();
      for (final version in job.invoiceVersions) {
        final versionId = version.id ?? version.invoiceNumber;
        final hasMatchingInvoice = versionId != null &&
            job.invoices.any((invoice) {
              return invoice.id == versionId ||
                  invoice.id == version.invoiceNumber;
            });
        if (!hasMatchingInvoice) {
          refreshedInvoices.add({'job': job, 'estimateVersion': version});
        }
      }
    }

    for (final job in allJobs) {
      for (final invoice in job.invoices) {
        refreshedInvoices.add({'job': job, 'invoice': invoice});
      }
    }

    return refreshedInvoices;
  }

  /// Fetches jobs directly from Firestore (bypassing the local disk cache,
  /// which doesn't exist/work on web) and rebuilds the invoices list from
  /// them. This solves the Navigator.push snapshot-staleness race
  /// condition described above `_refreshInvoicesFromCloud`'s call site.
  Future<void> _refreshInvoicesFromCloud() async {
    try {
      final cloudJobs = await FirebaseIntegrationService.loadJobs(
        onCloudUpdate: (updatedJobs) {
          if (mounted) {
            setState(() {
              _invoices = _buildInvoicesFromJobs(updatedJobs);
            });
          }
        },
      );
      if (mounted && cloudJobs.isNotEmpty) {
        setState(() {
          _invoices = _buildInvoicesFromJobs(cloudJobs);
        });
      }
    } catch (e) {
      print('⚠️ InvoicesScreen: failed to refresh invoices from cloud: $e');
    }
  }

  Future<void> _loadSentFollowUps() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> loadedDates = {};

    try {
      final jsonString = prefs.getString('sent_followup_invoices');
      if (jsonString != null && jsonString.isNotEmpty) {
        try {
          final decoded = json.decode(jsonString);
          if (decoded is Map<String, dynamic>) {
            loadedDates = decoded.map((key, value) => MapEntry(key, value?.toString() ?? ''));
          }
        } catch (_) {
          // Ignore invalid stored format
        }
      }
    } catch (e) {
      print('⚠️ Error loading sent follow-ups: $e');
    }

    if (mounted) {
      setState(() {
        _lastFollowUpSentDates = loadedDates;
      });
    }
  }

  Future<void> _markFollowUpSent(String invoiceKey) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().toIso8601String();

    setState(() {
      _lastFollowUpSentDates[invoiceKey] = timestamp;
    });

    await prefs.setString('sent_followup_invoices', json.encode(_lastFollowUpSentDates));
  }

  String? _formatFollowUpSentDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return null;
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _invoiceKey(Job job, dynamic invoice, dynamic estimateVersion) {
    if (invoice != null) {
      return '${job.id}:${invoice.id}';
    }
    if (estimateVersion != null) {
      return '${job.id}:${estimateVersion.invoiceNumber ?? estimateVersion.id ?? 'unknown'}';
    }
    return job.id;
  }

  Future<String> _loadFollowUpTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('followup_message') ??
        '''Hi There,

Friendly reminder that the attached invoice is now overdue, please disregard this if already paid.

Many Thanks''';
  }

  Future<void> _sendFollowUpEmail(
      Job job, dynamic invoice, dynamic estimateVersion) async {
    final toEmail = job.customerEmail;
    if (toEmail == null || toEmail.trim().isEmpty) {
      throw Exception('Customer email not available for this job.');
    }

    final template = await _loadFollowUpTemplate();
    final invoiceNumber = invoice != null
        ? invoice.id
        : estimateVersion?.invoiceNumber ?? estimateVersion?.id ?? 'Invoice';

    final body = template
        .replaceAll(
            '{customerName}',
            job.emailCustomerName.isNotEmpty
                ? job.emailCustomerName
                : 'Customer')
        .replaceAll('{invoiceNumber}', invoiceNumber)
        .replaceAll('{companyName}', '');

    final subject = 'Invoice #$invoiceNumber Follow Up';

    final attachmentPaths = <String>[];
    if (invoice?.filePath != null) {
      attachmentPaths.add(invoice.filePath!);
    } else if (estimateVersion?.filePath != null) {
      attachmentPaths.add(estimateVersion.filePath!);
    }

    await sendEmailViaSmtp(
      toEmails: [toEmail],
      subject: subject,
      body: body,
      attachmentPaths: attachmentPaths.isEmpty ? null : attachmentPaths,
    );

    final invoiceKey = _invoiceKey(job, invoice, estimateVersion);
    await _markFollowUpSent(invoiceKey);
  }

  /// Save job changes to persistent storage
  Future<void> _saveJobChanges(Job job) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      print('💾 [INVOICE DEBUG] _saveJobChanges starting for job: ${job.id}');
      print('💾 [INVOICE DEBUG] Invoice being saved: isPaid=${job.invoices.where((i) => i.isPaid).length}/${job.invoices.length} invoices marked paid');
      
      // Save to local storage
      final directory = await getApplicationDocumentsDirectory();

      // Save individual job file
      final jobFile = File('${directory.path}/job_${job.id}.json');
      await jobFile.writeAsString(jsonEncode(job.toJson()));
      print('💾 [INVOICE DEBUG] Saved to local job file: ${jobFile.path}');

      // Update main jobs.json file
      final mainJobsFile = File('${directory.path}/jobs.json');
      List<Job> allJobs = [];

      if (await mainJobsFile.exists()) {
        final jsonString = await mainJobsFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        allJobs = jsonList.map((e) => Job.fromJson(e)).toList();

        // Update the specific job in the list
        final jobIndex = allJobs.indexWhere((j) => j.id == job.id);
        if (jobIndex != -1) {
          allJobs[jobIndex] = job;
        } else {
          allJobs.add(job);
        }
      } else {
        allJobs = [job];
      }

      // Save updated jobs list
      final jsonList = allJobs.map((j) => j.toJson()).toList();
      await mainJobsFile.writeAsString(jsonEncode(jsonList));
      print('✅ Job saved successfully to local disk: ${job.id}');

      // Show success message immediately - don't wait for Firebase
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Payment status saved successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // 🔥 Save to Firebase IN THE BACKGROUND (non-blocking)
      // This way the UI updates instantly and Firebase syncs without blocking
      print('💾 [INVOICE DEBUG] Now saving to Firebase for job: ${job.id} (background)');
      FirebaseIntegrationService.saveJob(job).then((_) {
        print('✅ [INVOICE DEBUG] Job saved to Firebase successfully: ${job.id}');
      }).catchError((firebaseError) {
        print('❌ [INVOICE DEBUG] Failed to save to Firebase: $firebaseError');
        print('⚠️ [INVOICE DEBUG] LOCAL SAVE SUCCEEDED - invoice stays marked as paid locally');
      });
      
    } catch (e) {
      print('❌ Error saving job: $e');
      print('❌ [INVOICE DEBUG] Stack trace: ${StackTrace.current}');

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to save payment status: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  bool _isInvoiceArchived(dynamic invoice, dynamic estimateVersion) {
    return invoice?.isArchived == true || estimateVersion?.isArchived == true;
  }

  bool _isInvoicePaid(dynamic invoice, dynamic estimateVersion) {
    return invoice?.isPaid == true || estimateVersion?.isPaid == true;
  }

  /// Reloads all jobs from disk and rebuilds the flattened invoices list,
  /// mirroring the logic used when this screen is first opened (see
  /// `_openInvoicesScreen` in dashboard_screen.dart). This ensures the
  /// screen always reflects the latest data (e.g. new invoices created, or
  /// jobs edited, in other screens) rather than the potentially-stale list
  /// that was passed in via the constructor.
  Future<void> _reloadInvoicesFromDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final mainJobsFile = File('${directory.path}/jobs.json');
      if (!await mainJobsFile.exists()) return;

      final jsonString = await mainJobsFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final allJobs = jsonList.map((e) => Job.fromJson(e)).toList();

      final refreshedInvoices = <Map<String, dynamic>>[];

      for (final job in allJobs) {
        job.syncStatusFromDocuments();
        // Add invoice versions only when there is no matching Invoice object
        // already present (avoids double-counting).
        for (final version in job.invoiceVersions) {
          final versionId = version.id ?? version.invoiceNumber;
          final hasMatchingInvoice = versionId != null &&
              job.invoices.any((invoice) {
                return invoice.id == versionId ||
                    invoice.id == version.invoiceNumber;
              });
          if (!hasMatchingInvoice) {
            refreshedInvoices.add({'job': job, 'estimateVersion': version});
          }
        }
      }

      for (final job in allJobs) {
        for (final invoice in job.invoices) {
          refreshedInvoices.add({'job': job, 'invoice': invoice});
        }
      }

      if (mounted) {
        setState(() {
          _invoices = refreshedInvoices;
        });
      }
    } catch (e) {
      // Silently ignore; the screen will keep showing the last-known list.
    }
  }

  List<Map<String, dynamic>> get _filteredInvoices {
    List<Map<String, dynamic>> filtered = _invoices;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final job = item['job'] as Job;
        final invoice = item['invoice'];
        final estimateVersion = item['estimateVersion'];

        final customerName = (job.customerName ?? '').toLowerCase();
        final jobTitle = job.title.toLowerCase();
        final address = (job.address ?? '').toLowerCase();
        final searchLower = _searchQuery.toLowerCase();

        // Get amount and invoice number for search
        double amount;
        String invoiceNumber;

        if (invoice != null) {
          amount = invoice.amount;
          invoiceNumber = invoice.id;
        } else if (estimateVersion != null) {
          amount = estimateVersion.amount;
          invoiceNumber =
              estimateVersion.invoiceNumber ?? estimateVersion.id ?? '';
        } else {
          return false;
        }

        return customerName.contains(searchLower) ||
            jobTitle.contains(searchLower) ||
            address.contains(searchLower) ||
            amount.toString().contains(searchLower) ||
            invoiceNumber.toLowerCase().contains(searchLower);
      }).toList();
    }

    // Apply status filter
    if (_selectedStatus != InvoiceStatus.all) {
      filtered = filtered.where((item) {
        final invoice = item['invoice'];
        final estimateVersion = item['estimateVersion'];

        final isPaid = _isInvoicePaid(invoice, estimateVersion);
        final isArchived = _isInvoiceArchived(invoice, estimateVersion);
        final dueDate = invoice?.dueDate ?? estimateVersion?.dueDate;

        switch (_selectedStatus) {
          case InvoiceStatus.paid:
            return isPaid && !isArchived;
          case InvoiceStatus.overdue:
            if (isArchived || isPaid) return false;
            if (dueDate == null) return false;
            return DateTime.now().isAfter(dueDate);
          case InvoiceStatus.due:
            return !isPaid && !isArchived;
          case InvoiceStatus.archived:
            return isArchived;
          case InvoiceStatus.all:
            return true;
        }
      }).toList();
    }

    // Sort the results
    filtered.sort((a, b) {
      final jobA = a['job'] as Job;
      final jobB = b['job'] as Job;
      final invoiceA = a['invoice'];
      final invoiceB = b['invoice'];
      final versionA = a['estimateVersion'];
      final versionB = b['estimateVersion'];

      switch (_sortBy) {
        case 'customer':
          return (jobA.customerName ?? '').compareTo(jobB.customerName ?? '');
        case 'amount':
          final amountA =
              invoiceA != null ? invoiceA.amount : versionA?.amount ?? 0.0;
          final amountB =
              invoiceB != null ? invoiceB.amount : versionB?.amount ?? 0.0;
          return amountB.compareTo(amountA);
        case 'date':
        default:
          final dateA = invoiceA != null ? invoiceA.dueDate : versionA?.dueDate;
          final dateB = invoiceB != null ? invoiceB.dueDate : versionB?.dueDate;
          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateB.compareTo(dateA);
      }
    });

    return filtered;
  }

  double get _filteredTotal {
    return _filteredInvoices.fold<double>(0.0, (sum, item) {
      final invoice = item['invoice'];
      final estimateVersion = item['estimateVersion'];
      if (invoice != null) return sum + invoice.amount;
      if (estimateVersion != null) return sum + estimateVersion.amount;
      return sum;
    });
  }

  EstimateVersion? _findMatchingEstimateVersion(Job job, String invoiceId) {
    for (final version in job.estimateVersions) {
      if (version.id == invoiceId || version.invoiceNumber == invoiceId) {
        return version;
      }
    }
    return null;
  }

  Invoice? _findMatchingInvoice(Job job, EstimateVersion version) {
    for (final invoice in job.invoices) {
      if (invoice.id == version.id || invoice.id == version.invoiceNumber) {
        return invoice;
      }
    }
    return null;
  }

  void _replaceInvoiceInWidgetList(Job job, Invoice updatedInvoice) {
    for (final item in _invoices) {
      if (item['job'] == job && item['invoice'] != null) {
        final currentInvoice = item['invoice'] as Invoice;
        if (currentInvoice.id == updatedInvoice.id) {
          item['invoice'] = updatedInvoice;
        }
      }
    }
  }

  void _onInvoiceMenuAction(
      Job job, dynamic invoice, dynamic estimateVersion, String action) async {
    if (action == 'open_pdf') {
      final path =
          invoice != null ? invoice.filePath : estimateVersion?.filePath;
      if (path != null) await OpenFile.open(path);
      return;
    }

    if (action == 'view_builder') {
      final matchingVersion = invoice != null ? _findMatchingEstimateVersion(job, invoice.id) : estimateVersion;
      final buildId = matchingVersion?.builderBuildId;
      if (buildId != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EstimateBuilderScreen(
              job: job,
              inProgressBuildId: buildId,
            ),
          ),
        );
        await _reloadInvoicesFromDisk();
      }
      return;
    }

    if (action == 'open_job') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              JobDetailsScreen(job: job, priceBook: widget.priceBook),
        ),
      );
      await _reloadInvoicesFromDisk();
      return;
    }

    if (action == 'mark_paid') {
      if (invoice != null) {
        final updatedInvoice = invoice.copyWith(
          amountPaid: invoice.amount,
          isPaid: true,
          status: 'paid',
          paidVia: 'manual',
        );
        final invoiceIndex = job.invoices.indexWhere((inv) => inv.id == invoice.id);
        if (invoiceIndex != -1) {
          job.invoices[invoiceIndex] = updatedInvoice;
        }
        _replaceInvoiceInWidgetList(job, updatedInvoice);
        invoice = updatedInvoice;
      } else if (estimateVersion != null) {
        estimateVersion.isPaid = true;
        estimateVersion.paidVia = 'manual';
      }
    } else if (action == 'void') {
      if (invoice != null) {
        invoice.isArchived = true;
      } else if (estimateVersion != null) {
        estimateVersion.isArchived = true;
      }
    } else if (action == 'change_due_date') {
      final initial = invoice != null
          ? invoice.dueDate
          : estimateVersion?.dueDate ?? DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      );
      if (picked != null) {
        if (invoice != null) {
          invoice.dueDate = picked;
        } else if (estimateVersion != null) {
          estimateVersion.dueDate = picked;
        }
      }
    } else if (action == 'send_follow_up') {
      try {
        await _sendFollowUpEmail(job, invoice, estimateVersion);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Follow up email sent successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to send follow up email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (action == 'part_payment' && invoice != null) {
      final payment = await _promptInvoicePaymentDetails(invoice.balance);
      if (payment != null) {
        final updatedInvoice = invoice.addPayment(payment);
        final invoiceIndex = job.invoices.indexWhere((inv) => inv.id == invoice.id);
        if (invoiceIndex != -1) {
          job.invoices[invoiceIndex] = updatedInvoice;
        }
        _replaceInvoiceInWidgetList(job, updatedInvoice);
      }
    } else if (action == 'payment_history' && invoice != null) {
      await _showInvoicePaymentHistory(invoice);
    }

    if (action == 'mark_paid' ||
        action == 'void' ||
        action == 'change_due_date' ||
        action == 'part_payment') {
      if (invoice != null) {
        final matchingVersion = _findMatchingEstimateVersion(job, invoice.id);
        if (matchingVersion != null) {
          matchingVersion.isPaid = invoice.isPaid;
          matchingVersion.isArchived = invoice.isArchived;
        }
      } else if (estimateVersion != null) {
        final matchingInvoice = _findMatchingInvoice(job, estimateVersion);
        if (matchingInvoice != null) {
          matchingInvoice.isPaid = estimateVersion.isPaid;
          matchingInvoice.isArchived = estimateVersion.isArchived;
        }
      }
      job.syncInvoices();
      await _saveJobChanges(job);
    }

    setState(() {});
  }

  Future<void> _archiveInvoice(
      Job job, dynamic invoice, dynamic estimateVersion) async {
    if (invoice != null) {
      invoice.isArchived = true;
      final matchingVersion = _findMatchingEstimateVersion(job, invoice.id);
      if (matchingVersion != null) {
        matchingVersion.isArchived = true;
      }
    } else if (estimateVersion != null) {
      estimateVersion.isArchived = true;
      final matchingInvoice = _findMatchingInvoice(job, estimateVersion);
      if (matchingInvoice != null) {
        matchingInvoice.isArchived = true;
      }
    }
    job.syncInvoices();
    await _saveJobChanges(job);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invoice archived'),
        backgroundColor: Colors.green,
      ),
    );
    setState(() {});
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Reload from disk every time we return to this screen (e.g. after
    // viewing/editing a job, sending an invoice, etc.) so the list always
    // reflects the latest data rather than just repainting stale data.
    _reloadInvoicesFromDisk();
  }

  @override
  Widget build(BuildContext context) {
    final filteredInvoices = _filteredInvoices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'date', child: Text('Sort by Date')),
              PopupMenuItem(value: 'customer', child: Text('Sort by Customer')),
              PopupMenuItem(value: 'amount', child: Text('Sort by Amount')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(180),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Search bar
                TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText:
                        'Search by customer, job, address, amount, or invoice #',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _selectedStatus == InvoiceStatus.all,
                      onSelected: (_) =>
                          setState(() => _selectedStatus = InvoiceStatus.all),
                    ),
                    FilterChip(
                      label: const Text('Due'),
                      selected: _selectedStatus == InvoiceStatus.due,
                      onSelected: (_) =>
                          setState(() => _selectedStatus = InvoiceStatus.due),
                    ),
                    FilterChip(
                      label: const Text('Overdue'),
                      selected: _selectedStatus == InvoiceStatus.overdue,
                      onSelected: (_) => setState(
                          () => _selectedStatus = InvoiceStatus.overdue),
                    ),
                    FilterChip(
                      label: const Text('Paid'),
                      selected: _selectedStatus == InvoiceStatus.paid,
                      onSelected: (_) =>
                          setState(() => _selectedStatus = InvoiceStatus.paid),
                    ),
                    FilterChip(
                      label: const Text('Archived'),
                      selected: _selectedStatus == InvoiceStatus.archived,
                      onSelected: (_) => setState(
                          () => _selectedStatus = InvoiceStatus.archived),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${filteredInvoices.length} invoices',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey[700]),
                    ),
                    const Spacer(),
                    Text(
                      'Total: \$${_filteredTotal.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: filteredInvoices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isNotEmpty ||
                            _selectedStatus != InvoiceStatus.all
                        ? 'No invoices match your search criteria'
                        : 'No invoices found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (_searchQuery.isNotEmpty ||
                      _selectedStatus != InvoiceStatus.all) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                          _selectedStatus = InvoiceStatus.all;
                        });
                      },
                      child: const Text('Clear filters'),
                    ),
                  ],
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: filteredInvoices.length,
              itemBuilder: (context, index) {
                final job = filteredInvoices[index]['job'] as Job;
                final invoice = filteredInvoices[index]['invoice'];
                final estimateVersion =
                    filteredInvoices[index]['estimateVersion'];

                // Determine if this is an Invoice object or EstimateVersion
                DateTime? dueDate;
                double amount;
                double displayAmount;
                bool isPaid;
                bool isArchived;
                String invoiceNumber;
                String? filePath;
                String paidVia = 'manual';

                if (invoice != null) {
                  // Handle Invoice object
                  dueDate = invoice.dueDate;
                  amount = invoice.amount;
                  displayAmount = invoice.balance;
                  isPaid = invoice.isPaid;
                  isArchived = invoice.isArchived;
                  invoiceNumber = invoice.id;
                  filePath = invoice.filePath;
                  paidVia = invoice.paidVia;
                } else if (estimateVersion != null) {
                  // Handle EstimateVersion invoice
                  dueDate = estimateVersion.dueDate;
                  amount = estimateVersion.amount;
                  displayAmount = amount;
                  isPaid = estimateVersion.isPaid;
                  isArchived = estimateVersion.isArchived;
                  invoiceNumber = estimateVersion.invoiceNumber ??
                      estimateVersion.id ??
                      'N/A';
                  paidVia = estimateVersion.paidVia;
                  filePath = estimateVersion.filePath;
                } else {
                  return const SizedBox.shrink(); // Skip invalid entries
                }

                final daysPastDue = dueDate != null
                    ? DateTime.now().difference(dueDate).inDays
                    : null;

                final isOverdue = dueDate != null &&
                    !isPaid &&
                    !isArchived &&
                    daysPastDue != null &&
                    daysPastDue > 0;

                final matchingEstimateVersion = invoice != null ? _findMatchingEstimateVersion(job, invoice.id) : estimateVersion;
                final builderBuildId = matchingEstimateVersion?.builderBuildId;
                final followUpSentDate = _formatFollowUpSentDate(
                  _lastFollowUpSentDates[_invoiceKey(job, invoice, estimateVersion)],
                );
                final documentSent = (invoice?.emailSent == true) || (estimateVersion?.emailSent == true);
                final documentSentLabel = documentSent ? 'Sent' : 'Not sent';

                return Dismissible(
                  key: ValueKey(_invoiceKey(job, invoice, estimateVersion)),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.archive, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Archive',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.endToStart) {
                      return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Archive Invoice'),
                              content: const Text(
                                  'Are you sure you want to archive this invoice?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Archive'),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                    }
                    return false;
                  },
                  onDismissed: (direction) {
                    _archiveInvoice(job, invoice, estimateVersion);
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    elevation: 2,
                    child: InkWell(
                      onTap: () => _onInvoiceTap(job, invoice, estimateVersion),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 60,
                              decoration: BoxDecoration(
                                color: isPaid
                                    ? Colors.green
                                    : isOverdue
                                        ? Colors.red
                                        : Colors.orange,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Invoice #$invoiceNumber',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (filePath != null)
                                        const Icon(
                                          Icons.picture_as_pdf,
                                          size: 16,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Customer: ${job.customerName ?? "Unknown"}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  Text(
                                    'Job: ${job.title}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  if (job.address != null)
                                    Text(
                                      'Address: ${job.address}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  if (invoice != null)
                                    Text(
                                      'Invoice: \$${invoice.amount.toStringAsFixed(2)} • Paid: \$${invoice.amountPaid.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  Text(
                                    documentSentLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: documentSent ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  if (followUpSentDate != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Last follow up email sent $followUpSentDate',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '\$${displayAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: isArchived
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: const Text(
                                                    'ARCHIVED',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                )
                                              : isPaid
                                                  ? Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green,
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Text(
                                                        paidVia == 'xero'
                                                            ? 'PAID (XERO)'
                                                            : 'MARKED PAID',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    )
                                                  : isOverdue
                                                      ? Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.red,
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: Text(
                                                            '$daysPastDue DAYS OVERDUE',
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                            maxLines: 1,
                                                          ),
                                                        )
                                                      : Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.orange,
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: Text(
                                                            dueDate != null
                                                                ? 'DUE ${dueDate.day}/${dueDate.month}/${dueDate.year}'
                                                                : 'DUE DATE NOT SET',
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                            maxLines: 1,
                                                          ),
                                                        ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_lastFollowUpSentDates.containsKey(_invoiceKey(job, invoice, estimateVersion)))
                                    Text(
                                      'Last follow-up: ${_formatFollowUpSentDate(_lastFollowUpSentDates[_invoiceKey(job, invoice, estimateVersion)])}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.grey),
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'open_job',
                                  child: Text('Open Job'),
                                ),
                                if (builderBuildId != null) ...[
                                  const PopupMenuItem<String>(
                                    value: 'view_builder',
                                    child: Text('View in Builder'),
                                  ),
                                ],
                                const PopupMenuItem<String>(
                                  value: 'open_pdf',
                                  child: Text('Open PDF'),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'mark_paid',
                                  child: Text('Mark as Paid'),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'void',
                                  child: Text('Archive Invoice'),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'change_due_date',
                                  child: Text('Change Due Date'),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'send_follow_up',
                                  child: Text('Send Follow Up Email'),
                                ),
                                if (invoice != null)
                                  const PopupMenuItem<String>(
                                    value: 'payment_history',
                                    child: Text('Payment History'),
                                  ),
                                if (invoice != null && !invoice.isArchived && !invoice.isPaid)
                                  const PopupMenuItem<String>(
                                    value: 'part_payment',
                                    child: Text('Add Part Payment'),
                                  ),
                              ],
                              onSelected: (String value) {
                                _onInvoiceMenuAction(job, invoice, estimateVersion, value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _onInvoiceTap(Job job, dynamic invoice, dynamic estimateVersion) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailsScreen(job: job, priceBook: widget.priceBook),
      ),
    ).then((_) {
      _reloadInvoicesFromDisk();
    });
  }

  Future<void> _showInvoicePaymentHistory(Invoice invoice) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Payment History'),
          content: invoice.payments.isEmpty
              ? const Text('No payments recorded yet.')
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: invoice.payments.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final payment = invoice.payments[index];
                      return ListTile(
                        dense: true,
                        title: Text('\$${payment.amount.toStringAsFixed(2)}'),
                        subtitle: Text(
                            '${payment.date.day}/${payment.date.month}/${payment.date.year}${payment.note != null ? ' — ${payment.note}' : ''}'),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<InvoicePayment?> _promptInvoicePaymentDetails(double balance) async {
    final amountController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    return showDialog<InvoicePayment>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Record Part Payment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Remaining balance: \$${balance.toStringAsFixed(2)}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Payment amount',
                      prefixText: '\$',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Payment date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amount = double.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0 || amount > balance) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid payment amount.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop(InvoicePayment(
                      amount: amount,
                      date: selectedDate,
                    ));
                  },
                  child: const Text('Save Payment'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
