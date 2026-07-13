import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'estimate_item.dart';
import 'estimate_version.dart';
import 'invoice.dart'; // or wherever your Invoice class is

/// Job status history entry
class JobStatusHistory {
  final JobStatus status;
  final DateTime timestamp;
  final String? reason; // Optional reason for status change
  final String? documentId; // ID of related document (estimate/invoice)

  JobStatusHistory({
    required this.status,
    required this.timestamp,
    this.reason,
    this.documentId,
  });

  factory JobStatusHistory.fromJson(Map<String, dynamic> json) {
    return JobStatusHistory(
      status: JobStatus.fromString(json['status']),
      timestamp: DateTime.parse(json['timestamp']),
      reason: json['reason'],
      documentId: json['documentId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'reason': reason,
      'documentId': documentId,
    };
  }
}

/// Job status enum with priority order (higher priority = more recent status)
enum JobStatus {
  active, // 0 - Default status
  estimateCreated, // 1 - Estimate/Quote Created (triggered by creating PDF)
  estimateSent, // 2 - Estimate/Quote sent (triggered by email sent with estimate attached)
  invoiceCreated, // 3 - Invoice Created (triggered by creating PDF)
  invoiceSent, // 4 - Invoice sent (triggered by email sent with invoice attached)
  invoicePaid, // 5 - Invoice Paid (triggered by invoice getting paid)
  jobComplete, // 6 - Job complete (question after invoice sent via email)
  archived; // 7 - Archived

  String get displayName {
    switch (this) {
      case JobStatus.active:
        return 'Active';
      case JobStatus.estimateCreated:
        return 'Estimate/Quote Created';
      case JobStatus.estimateSent:
        return 'Estimate/Quote Sent';
      case JobStatus.invoiceCreated:
        return 'Invoice Created';
      case JobStatus.invoiceSent:
        return 'Invoice Sent';
      case JobStatus.invoicePaid:
        return 'Invoice Paid';
      case JobStatus.jobComplete:
        return 'Job Complete';
      case JobStatus.archived:
        return 'Archived';
    }
  }

  /// Get priority for status updates (higher number = higher priority)
  int get priority => index;

  static JobStatus fromString(String? status) {
    if (status == null) return JobStatus.active;
    return JobStatus.values.firstWhere(
      (s) =>
          s.name.toLowerCase() == status.toLowerCase() ||
          s.displayName.toLowerCase() == status.toLowerCase(),
      orElse: () => JobStatus.active,
    );
  }
}

class Job {
  String id;
  String title;
  String? description;
  String? customerName;
  String? companyName;
  String? bodyCorporateNumber;
  final String? referenceNumber;
  String? address;
  String? orderNumber;

  /// Use company name for document headers when available, otherwise fall back to the customer name.
  String get documentCustomerName {
    if (companyName != null && companyName!.trim().isNotEmpty) {
      return companyName!;
    }
    return customerName ?? '';
  }

  /// Use customer name for emails if available, otherwise fall back to company name.
  String get emailCustomerName {
    if (customerName != null && customerName!.trim().isNotEmpty) {
      return customerName!;
    }
    return companyName ?? '';
  }

  JobStatus currentStatus;
  /// When this job was created. Always guaranteed to be non-null (defaults
  /// to "now" if not provided) so that Firestore's orderBy('created') query
  /// never silently excludes a job document for missing this field.
  final DateTime created;
  final DateTime? dueDate;
  final String? jobType;
  List<EstimateItem> estimateItems;
  List<EstimateVersion> estimateVersions;
  String? paymentTerms;
  List<String>? attachments;
  String? customerEmail;
  Invoice? invoice;
  List<Invoice> invoices;
  List<String>? notes;
  List<JobStatusHistory> statusHistory;
  final List<DateTime>? scheduleDates;
  final bool isFlexibleDayJob; // True if this job repeats every day (no specific date)

  Job({
    required this.id,
    required this.title,
    this.description,
    this.customerName,
    this.companyName,
    this.bodyCorporateNumber,
    this.referenceNumber,
    this.address,
    this.orderNumber,
    JobStatus? status,
    DateTime? created,
    this.dueDate,
    this.jobType,
    List<EstimateItem>? estimateItems,
    this.customerEmail,
    this.paymentTerms,
    this.attachments,
    List<EstimateVersion>? estimateVersions,
    this.invoice,
    List<Invoice>? invoices,
    this.notes,
    List<JobStatusHistory>? statusHistory,
    this.scheduleDates,
    this.isFlexibleDayJob = false,
  })  : currentStatus = status ?? JobStatus.active,
        created = created ?? DateTime.now(),
        estimateItems = estimateItems ?? [],
        estimateVersions = estimateVersions ?? [],
        invoices = invoices ?? [],
        statusHistory = statusHistory ?? [];

  Job copyWith({
    String? id,
    String? title,
    String? customerName,
    String? companyName,
    String? bodyCorporateNumber,
    String? referenceNumber,
    JobStatus? status,
    DateTime? created,
    DateTime? dueDate,
    String? jobType,
    String? address,
    String? orderNumber,
    List<EstimateItem>? estimateItems,
    String? customerEmail,
    String? paymentTerms,
    List<String>? attachments,
    Invoice? invoice,
    List<Invoice>? invoices,
    List<String>? notes,
    List<JobStatusHistory>? statusHistory,
    List<DateTime>? scheduleDates,
    List<EstimateVersion>? estimateVersions,
    bool? isFlexibleDayJob,
  }) {
    return Job(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      customerName: customerName ?? this.customerName,
      companyName: companyName ?? this.companyName,
      bodyCorporateNumber: bodyCorporateNumber ?? this.bodyCorporateNumber,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      address: address ?? this.address,
      orderNumber: orderNumber ?? this.orderNumber,
      status: status ?? currentStatus,
      created: created ?? this.created,
      dueDate: dueDate ?? this.dueDate,
      jobType: jobType ?? this.jobType,
      estimateItems: estimateItems ?? this.estimateItems,
      customerEmail: customerEmail ?? this.customerEmail,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      attachments: attachments ?? this.attachments,
      estimateVersions: estimateVersions ?? this.estimateVersions,
      invoice: invoice ?? this.invoice,
      invoices: invoices ?? this.invoices,
      notes: notes ?? this.notes,
      statusHistory: statusHistory ?? this.statusHistory,
      scheduleDates: scheduleDates ?? this.scheduleDates,
      isFlexibleDayJob: isFlexibleDayJob ?? this.isFlexibleDayJob,
    );
  }

  factory Job.fromJson(Map<String, dynamic> json) {
    final job = Job(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description'] as String?,
      customerName: json['customerName'] as String?,
      companyName: json['companyName'] as String?,
      bodyCorporateNumber: json['bodyCorporateNumber'] as String?,
      referenceNumber: json['referenceNumber'] as String?,
      address: json['address'] as String?,
      orderNumber: json['orderNumber'] as String?,
      status: JobStatus.fromString(json['status'] as String?),
      // Guard against missing/unparseable 'created' values (e.g. from older
      // data or partial syncs) so a job is never silently excluded from
      // Firestore orderBy('created') queries due to a null/invalid field.
      created: json['created'] != null
          ? (DateTime.tryParse(json['created'] as String) ?? DateTime.now())
          : DateTime.now(),
      dueDate: json['dueDate'] != null
          ? DateTime.tryParse(json['dueDate'] as String)
          : null,
      jobType: json['jobType'] as String?,
      estimateItems: (json['estimateItems'] is List
              ? json['estimateItems'] as List<dynamic>
              : null)
          ?.map((item) => EstimateItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      customerEmail: json['customerEmail'] as String?,
      paymentTerms: json['paymentTerms'] as String?,
      attachments: (json['attachments'] is List
              ? json['attachments'] as List
              : null)
          ?.map((e) => e.toString())
          .toList(),
      estimateVersions: (json['estimateVersions'] is List
              ? json['estimateVersions'] as List<dynamic>
              : null)
          ?.map((e) => EstimateVersion.fromJson(e))
          .toList(),
      invoices: (json['invoices'] is List ? json['invoices'] as List<dynamic> : null)
          ?.map((e) => Invoice.fromJson(e))
          .toList(),
      notes: (json['notes'] is List ? json['notes'] as List : null)
          ?.map((e) => e.toString())
          .toList(),
      statusHistory: (json['statusHistory'] is List
              ? json['statusHistory'] as List<dynamic>
              : null)
          ?.map((e) => JobStatusHistory.fromJson(e))
          .toList(),
      scheduleDates: (json['scheduleDates'] is List
              ? json['scheduleDates'] as List<dynamic>
              : null)
          ?.map((e) => DateTime.tryParse(e as String))
          .whereType<DateTime>()
          .toList(),
      isFlexibleDayJob: json['isFlexibleDayJob'] as bool? ?? false,
    );

    // Sync invoices after loading
    job.syncInvoices();
    return job;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'customerName': customerName,
      'companyName': companyName,
      'bodyCorporateNumber': bodyCorporateNumber,
      'referenceNumber': referenceNumber,
      'address': address,
      'orderNumber': orderNumber,
      'status': currentStatus.name,
      'created': created.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'jobType': jobType,
      'estimateItems': estimateItems.map((item) => item.toJson()).toList(),
      'customerEmail': customerEmail,
      'paymentTerms': paymentTerms,
      'attachments': attachments,
      'estimateVersions': estimateVersions.map((e) => e.toJson()).toList(),
      'invoices': invoices.map((e) => e.toJson()).toList(),
      'notes': notes,
      'statusHistory': statusHistory.map((e) => e.toJson()).toList(),
      'scheduleDates': scheduleDates?.map((date) => date.toIso8601String()).toList(),
      'isFlexibleDayJob': isFlexibleDayJob,
    };
  }

  List<EstimateVersion> get estimates => estimateVersions
      .where((v) =>
          (v.type == 'estimate' || v.type == 'quote') &&
          v.status != 'in_progress')
      .toList();

  List<EstimateVersion> get invoiceVersions =>
      estimateVersions.where((v) => v.type == 'invoice').toList();

  // Helper method to sync EstimateVersion invoices to Invoice objects
  void syncInvoices() {
    // Instead of clearing all invoices, be more selective to preserve manual updates

    // First, update existing Invoice objects with data from EstimateVersions
    for (final version in invoiceVersions) {
      final existingInvoiceIndex = invoices.indexWhere((inv) =>
          inv.id == version.id ||
          inv.id == version.invoiceNumber ||
          (inv.total == version.amount && inv.customerName == customerName));

      if (existingInvoiceIndex != -1) {
        // Update existing invoice, preserving any manual updates like isPaid status
        final existingInvoice = invoices[existingInvoiceIndex];
        final nowPaid = existingInvoice.isPaid || version.isPaid;
        final updatedInvoice = Invoice(
          id: version.id ?? version.invoiceNumber ?? existingInvoice.id,
          total: version.amount,
          amount: version.amount,
          amountPaid: existingInvoice.amountPaid,
          payments: existingInvoice.payments,
          emailSent: existingInvoice.emailSent || version.emailSent,
          // Preserve the paid status if it was manually set, otherwise use EstimateVersion status
          isPaid: nowPaid,
          dueDate: version.dueDate,
          customerId: id,
          customerName: customerName ?? 'Unknown',
          status: nowPaid
              ? 'paid'
              : version.isArchived
                  ? 'archived'
                  : 'unpaid',
          isArchived: version.isArchived,
          filePath: version.filePath,
          // Prefer whichever side already recorded a paidVia (already-paid
          // wins), otherwise fall back to the EstimateVersion's.
          paidVia: existingInvoice.isPaid
              ? existingInvoice.paidVia
              : version.paidVia,
        );
        invoices[existingInvoiceIndex] = updatedInvoice;

        // Also sync the paid status back to EstimateVersion if it was manually updated
        if (existingInvoice.isPaid && !version.isPaid) {
          version.isPaid = true;
          version.paidVia = existingInvoice.paidVia;
          print(
              '✅ Synced manual payment status back to EstimateVersion: ${version.id}');
        }
      } else {
        // Create new invoice only if it doesn't exist
        final newInvoice = Invoice(
          id: version.id ??
              version.invoiceNumber ??
              'inv-${DateTime.now().millisecondsSinceEpoch}',
          total: version.amount,
          amount: version.amount,
          amountPaid: version.isPaid ? version.amount : 0.0,
          payments: [],
          emailSent: version.emailSent,
          isPaid: version.isPaid,
          dueDate: version.dueDate,
          customerId: id,
          customerName: customerName ?? 'Unknown',
          status: version.isPaid
              ? 'paid'
              : version.isArchived
                  ? 'archived'
                  : 'unpaid',
          isArchived: version.isArchived,
          filePath: version.filePath,
          paidVia: version.paidVia,
        );
        invoices.add(newInvoice);
      }
    }

    // Remove invoices that no longer have corresponding EstimateVersions
    // BUT PRESERVE THE FILE PATH - don't delete the actual PDF file!
    final invoicesToRemove = <String>[];
    invoices.removeWhere((inv) {
      final hasMatch = invoiceVersions.any((v) =>
          v.id == inv.id ||
          v.invoiceNumber == inv.id ||
          (v.amount == inv.total && v.type == 'invoice'));
      if (!hasMatch) {
        // Log which invoice is being removed and preserve its file path
        print('⚠️ Removing orphaned invoice from list: ${inv.id} (filePath: ${inv.filePath})');
        if (inv.filePath != null) {
          invoicesToRemove.add(inv.filePath!);
        }
      }
      return !hasMatch;
    });
  }

  // Get all outstanding invoice amounts (both from EstimateVersions and Invoice objects)
  double get totalOutstandingAmount {
    double total = 0.0;

    // Add from EstimateVersion invoices
    for (final version in invoiceVersions) {
      if (!version.isPaid && !version.isArchived) {
        total += version.amount;
      }
    }

    // Add from Invoice objects (avoid double counting by checking IDs)
    for (final invoice in invoices) {
      if (!invoice.isPaid && !invoice.isArchived) {
        // Only add if this invoice doesn't correspond to an EstimateVersion
        final hasMatchingVersion = invoiceVersions
            .any((v) => v.id == invoice.id || v.invoiceNumber == invoice.id);
        if (!hasMatchingVersion) {
          total += invoice.amount;
        }
      }
    }

    return total;
  }

  /// Update job status with automatic priority handling
  void updateStatus(JobStatus newStatus, {String? reason, String? documentId}) {
    // Only update if new status has higher or equal priority
    if (newStatus.priority >= currentStatus.priority) {
      // Add to history
      statusHistory.add(JobStatusHistory(
        status: newStatus,
        timestamp: DateTime.now(),
        reason: reason,
        documentId: documentId,
      ));

      currentStatus = newStatus;
    }
  }

  /// Trigger status updates based on document events
  void onEstimateCreated(String documentId) {
    updateStatus(JobStatus.estimateCreated,
        reason: 'Estimate/Quote PDF created', documentId: documentId);
  }

  void onEstimateSent(String documentId) {
    updateStatus(JobStatus.estimateSent,
        reason: 'Estimate/Quote sent via email', documentId: documentId);
  }

  void onInvoiceCreated(String documentId) {
    updateStatus(JobStatus.invoiceCreated,
        reason: 'Invoice PDF created', documentId: documentId);
  }

  void onInvoiceSent(String documentId) {
    updateStatus(JobStatus.invoiceSent,
        reason: 'Invoice sent via email', documentId: documentId);
  }

  void onInvoicePaid(String documentId) {
    updateStatus(JobStatus.invoicePaid,
        reason: 'Invoice marked as paid', documentId: documentId);
  }

  void onJobComplete() {
    updateStatus(JobStatus.jobComplete, reason: 'Job marked as complete');
  }

  /// Handle special case: both estimate and invoice sent in same email
  void onEstimateAndInvoiceSent(String estimateId, String invoiceId) {
    // Always prioritize estimate sent when both are sent together
    updateStatus(JobStatus.estimateSent,
        reason: 'Estimate and Invoice sent together (prioritizing estimate)',
        documentId: estimateId);
  }

  /// Get the latest status from estimate/invoice versions and auto-update
  void syncStatusFromDocuments() {
    // Track the highest priority status found
    JobStatus highestStatus = JobStatus.active;
    String? documentId;
    String? reason;

    // Check estimates/quotes
    for (final version in estimateVersions) {
      if (version.type == 'estimate' || version.type == 'quote') {
        if (version.filePath != null) {
          // Document was created
          if (JobStatus.estimateCreated.priority > highestStatus.priority) {
            highestStatus = JobStatus.estimateCreated;
            documentId = version.id;
            reason = 'Estimate/Quote PDF found';
          }
        }
        // Add logic here for sent status when email tracking is implemented
      }
    }

    // Check invoices
    for (final version in estimateVersions) {
      if (version.type == 'invoice') {
        if (version.filePath != null) {
          // Invoice was created
          if (JobStatus.invoiceCreated.priority > highestStatus.priority) {
            highestStatus = JobStatus.invoiceCreated;
            documentId = version.id;
            reason = 'Invoice PDF found';
          }
        }

        if (version.isPaid) {
          // Invoice was paid
          if (JobStatus.invoicePaid.priority > highestStatus.priority) {
            highestStatus = JobStatus.invoicePaid;
            documentId = version.id;
            reason = 'Invoice marked as paid';
          }
        }
      }
    }

    // Update if we found a higher priority status
    if (highestStatus.priority > currentStatus.priority) {
      updateStatus(highestStatus, reason: reason, documentId: documentId);
    }
  }

  /// Get display name for current status
  String get statusDisplayName => currentStatus.displayName;

  /// Check if job matches any of the given statuses
  bool matchesStatuses(List<JobStatus> statuses) {
    return statuses.contains(currentStatus);
  }

  Future<void> save() async {
    try {
      // Get the application documents directory
      final directory = await getApplicationDocumentsDirectory();
      final jobsDir = Directory('${directory.path}/jobs');

      // Create jobs directory if it doesn't exist
      if (!await jobsDir.exists()) {
        await jobsDir.create(recursive: true);
      }

      // Save job data to JSON file (local backup)
      final jobFile = File('${jobsDir.path}/$id.json');
      final jobData = toJson();
      await jobFile.writeAsString(jsonEncode(jobData));

      // Also update the main jobs.json file with all jobs
      final mainJobsFile = File('${directory.path}/jobs.json');
      List<Job> allJobs = [];

      // Load existing jobs
      if (await mainJobsFile.exists()) {
        try {
          final jsonString = await mainJobsFile.readAsString();
          if (jsonString.trim().isNotEmpty) {
            final List<dynamic> jsonList = jsonDecode(jsonString);
            allJobs = jsonList.map((e) => Job.fromJson(e)).toList();
          }
        } catch (e) {
          print('Error loading existing jobs: $e');
        }
      }

      // Update or add this job
      final existingIndex = allJobs.indexWhere((job) => job.id == id);
      if (existingIndex >= 0) {
        allJobs[existingIndex] = this;
      } else {
        allJobs.add(this);
      }

      // Save all jobs back to main file
      final allJobsJson = allJobs.map((job) => job.toJson()).toList();
      await mainJobsFile.writeAsString(jsonEncode(allJobsJson));

      print('✅ Job saved successfully to local storage: $id');

      // Try to sync to Firebase if available
      try {
        // Import Firebase service here to avoid circular imports
        // This will be handled by the Firebase integration service
        print('🔄 Job will be synced to Firebase by integration service');
      } catch (e) {
        print('⚠️ Firebase sync not available: $e');
      }
    } catch (e) {
      print('❌ Error saving job: $e');
      rethrow;
    }
  }
}
