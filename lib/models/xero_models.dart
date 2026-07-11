// Data models and payload helpers for the Xero sync engine.
//
// These types map our local domain objects (Job, Invoice, EstimateItem)
// onto the exact JSON shapes the Xero Accounting API expects, and back
// (for webhook/reconciliation events). Kept dependency-free (no Isar/Dio)
// so they can be unit tested in isolation and reused by both the
// background push worker and the webhook parser.

/// How GST/tax is expressed on the line items we send to Xero.
enum XeroLineAmountType { exclusive, inclusive, noTax }

extension XeroLineAmountTypeX on XeroLineAmountType {
  String get wireValue {
    switch (this) {
      case XeroLineAmountType.exclusive:
        return 'Exclusive';
      case XeroLineAmountType.inclusive:
        return 'Inclusive';
      case XeroLineAmountType.noTax:
        return 'NoTax';
    }
  }
}

/// Local <-> Xero sync status for an invoice (or any synced entity).
enum XeroSyncStatus {
  notSynced,
  pending,
  synced,
  failed,
  voided,
}

/// A single line item as Xero expects it under `Invoices[].LineItems[]`.
class XeroLineItem {
  final String description;
  final double quantity;
  final double unitAmount;
  final String accountCode;
  final String taxType;

  /// Our local price-book / estimate item id, preserved as `ItemCode` when
  /// available so the exact item can be round-tripped/identified in Xero.
  final String? itemCode;

  const XeroLineItem({
    required this.description,
    required this.quantity,
    required this.unitAmount,
    required this.accountCode,
    required this.taxType,
    this.itemCode,
  });

  Map<String, dynamic> toJson() => {
        'Description': description,
        'Quantity': quantity,
        'UnitAmount': unitAmount,
        'AccountCode': accountCode,
        'TaxType': taxType,
        if (itemCode != null && itemCode!.isNotEmpty) 'ItemCode': itemCode,
      };
}

/// Maps to Xero's `Contact` object, either referencing an existing
/// ContactID or supplying a Name so Xero creates a new contact inline.
class XeroContact {
  final String? contactId;
  final String? name;
  final String? emailAddress;

  const XeroContact({this.contactId, this.name, this.emailAddress});

  Map<String, dynamic> toJson() {
    if (contactId != null && contactId!.isNotEmpty) {
      return {'ContactID': contactId};
    }
    return {
      'Name': name ?? 'Unknown Customer',
      if (emailAddress != null && emailAddress!.isNotEmpty)
        'EmailAddress': emailAddress,
    };
  }
}

/// Full payload for Xero's `PUT /Invoices` endpoint (one invoice).
///
/// `reference` / `invoiceNumber` are always populated from our local
/// invoice id so retried pushes are idempotent from Xero's point of view
/// (Xero treats a duplicate InvoiceNumber within a contact as an update,
/// not a new invoice, when using the correct sync approach - see
/// [XeroInvoiceRepository] for the actual dedupe/lookup logic).
class XeroInvoicePayload {
  final String? xeroInvoiceId; // set once known, for updates
  final XeroContact contact;
  final String invoiceNumber; // our local invoice/document number
  final String reference; // our local unique DB id, for idempotency
  final DateTime date;
  final DateTime? dueDate;
  final XeroLineAmountType lineAmountTypes;
  final List<XeroLineItem> lineItems;
  final String status; // 'DRAFT' | 'SUBMITTED' | 'AUTHORISED' | 'PAID'

  const XeroInvoicePayload({
    this.xeroInvoiceId,
    required this.contact,
    required this.invoiceNumber,
    required this.reference,
    required this.date,
    this.dueDate,
    this.lineAmountTypes = XeroLineAmountType.exclusive,
    required this.lineItems,
    this.status = 'AUTHORISED',
  });

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        if (xeroInvoiceId != null && xeroInvoiceId!.isNotEmpty)
          'InvoiceID': xeroInvoiceId,
        'Type': 'ACCREC',
        'Contact': contact.toJson(),
        'LineAmountTypes': lineAmountTypes.wireValue,
        'InvoiceNumber': invoiceNumber,
        'Reference': reference,
        'Date': _fmtDate(date),
        if (dueDate != null) 'DueDate': _fmtDate(dueDate!),
        'LineItems': lineItems.map((li) => li.toJson()).toList(),
        'Status': status,
      };
}

/// Payload for Xero's `PUT /Payments` endpoint, reconciling a payment
/// against an already-pushed invoice.
class XeroPaymentPayload {
  final String xeroInvoiceId;
  final String accountCode;
  final DateTime date;
  final double amount;

  const XeroPaymentPayload({
    required this.xeroInvoiceId,
    required this.accountCode,
    required this.date,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'Payment': {
          'Invoice': {'InvoiceID': xeroInvoiceId},
          'Account': {'Code': accountCode},
          'Date':
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'Amount': amount,
        },
      };
}

/// A cached Xero Chart of Accounts entry (from `/Accounts`).
class XeroAccount {
  final String code;
  final String name;
  final String type; // e.g. 'REVENUE', 'BANK'
  final String? taxType;

  const XeroAccount({
    required this.code,
    required this.name,
    required this.type,
    this.taxType,
  });

  factory XeroAccount.fromJson(Map<String, dynamic> json) => XeroAccount(
        code: json['Code']?.toString() ?? '',
        name: json['Name']?.toString() ?? '',
        type: json['Type']?.toString() ?? '',
        taxType: json['TaxType']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'Code': code,
        'Name': name,
        'Type': type,
        if (taxType != null) 'TaxType': taxType,
      };
}

/// A cached Xero Tax Rate entry (from `/TaxRates`).
class XeroTaxRate {
  final String name;
  final String taxType; // e.g. 'OUTPUT'
  final double effectiveRate;

  const XeroTaxRate({
    required this.name,
    required this.taxType,
    required this.effectiveRate,
  });

  factory XeroTaxRate.fromJson(Map<String, dynamic> json) => XeroTaxRate(
        name: json['Name']?.toString() ?? '',
        taxType: json['TaxType']?.toString() ?? '',
        effectiveRate: (json['EffectiveRate'] ?? json['DisplayTaxRate'] ?? 0)
            .toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'Name': name,
        'TaxType': taxType,
        'EffectiveRate': effectiveRate,
      };
}

/// Persistent local <-> Xero id mapping for a single invoice, used both
/// for idempotency (never push the same local invoice twice as a new
/// Xero invoice) and for two-way payment reconciliation.
class XeroInvoiceSyncRecord {
  final String localInvoiceId; // our Invoice.id / job invoice key
  final String? jobId; // the Job that owns this invoice, for reconciliation
  final String? xeroInvoiceId;
  final XeroSyncStatus status;
  final DateTime? lastSyncedAt;
  final String? lastError;

  const XeroInvoiceSyncRecord({
    required this.localInvoiceId,
    this.jobId,
    this.xeroInvoiceId,
    this.status = XeroSyncStatus.notSynced,
    this.lastSyncedAt,
    this.lastError,
  });

  XeroInvoiceSyncRecord copyWith({
    String? jobId,
    String? xeroInvoiceId,
    XeroSyncStatus? status,
    DateTime? lastSyncedAt,
    String? lastError,
  }) =>
      XeroInvoiceSyncRecord(
        localInvoiceId: localInvoiceId,
        jobId: jobId ?? this.jobId,
        xeroInvoiceId: xeroInvoiceId ?? this.xeroInvoiceId,
        status: status ?? this.status,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: lastError,
      );

  Map<String, dynamic> toJson() => {
        'localInvoiceId': localInvoiceId,
        'jobId': jobId,
        'xeroInvoiceId': xeroInvoiceId,
        'status': status.name,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'lastError': lastError,
      };

  factory XeroInvoiceSyncRecord.fromJson(Map<String, dynamic> json) =>
      XeroInvoiceSyncRecord(
        localInvoiceId: json['localInvoiceId'] as String,
        jobId: json['jobId'] as String?,
        xeroInvoiceId: json['xeroInvoiceId'] as String?,
        status: XeroSyncStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => XeroSyncStatus.notSynced,
        ),
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.tryParse(json['lastSyncedAt'] as String)
            : null,
        lastError: json['lastError'] as String?,
      );
}

/// Minimal shape describing a Xero webhook event payload for invoices,
/// as delivered by Xero's webhook system (`https://developer.xero.com/documentation/api/accounting/webhooks`).
class XeroWebhookInvoiceEvent {
  final String xeroInvoiceId;
  final String eventCategory; // e.g. 'INVOICE'
  final String eventType; // e.g. 'UPDATE'
  final DateTime eventDate;

  const XeroWebhookInvoiceEvent({
    required this.xeroInvoiceId,
    required this.eventCategory,
    required this.eventType,
    required this.eventDate,
  });

  factory XeroWebhookInvoiceEvent.fromJson(Map<String, dynamic> json) =>
      XeroWebhookInvoiceEvent(
        xeroInvoiceId: json['resourceId']?.toString() ?? '',
        eventCategory: json['eventCategory']?.toString() ?? '',
        eventType: json['eventType']?.toString() ?? '',
        eventDate: DateTime.tryParse(json['eventDateUtc']?.toString() ?? '') ??
            DateTime.now(),
      );
}
