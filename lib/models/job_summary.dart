/// Lightweight summary of a Job used for list views.
/// Contains only essential fields to avoid OutOfMemoryError when loading 100+ jobs.
/// Full job details are fetched on-demand when the user taps into a specific job.
class JobSummary {
  final String id;
  final String title;
  final String? customerName;
  final String? address;
  final DateTime created;
  final DateTime? updated;
  final String status; // e.g. "Active", "Invoice Paid", etc.
  final double? totalAmount; // Sum of all invoices or estimates
  final bool hasUnpaidInvoices; // Quick flag for UI
  final int invoiceCount; // Number of invoices (for UI badges)
  final int estimateCount; // Number of estimates (for UI badges)

  JobSummary({
    required this.id,
    required this.title,
    this.customerName,
    this.address,
    required this.created,
    this.updated,
    required this.status,
    this.totalAmount,
    this.hasUnpaidInvoices = false,
    this.invoiceCount = 0,
    this.estimateCount = 0,
  });

  /// Create a summary from JSON (from Firestore)
  factory JobSummary.fromJson(Map<String, dynamic> json) {
    return JobSummary(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      customerName: json['customerName'],
      address: json['address'],
      created: json['created'] is DateTime
          ? json['created']
          : DateTime.tryParse(json['created']?.toString() ?? '') ?? DateTime.now(),
      updated: json['updated'] is DateTime
          ? json['updated']
          : DateTime.tryParse(json['updated']?.toString() ?? ''),
      status: json['status'] ?? 'active',
      totalAmount: (json['totalAmount'] as num?)?.toDouble(),
      hasUnpaidInvoices: json['hasUnpaidInvoices'] ?? false,
      invoiceCount: json['invoiceCount'] ?? 0,
      estimateCount: json['estimateCount'] ?? 0,
    );
  }

  /// Convert to JSON for local storage or cloud
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'customerName': customerName,
      'address': address,
      'created': created.toIso8601String(),
      'updated': updated?.toIso8601String(),
      'status': status,
      'totalAmount': totalAmount,
      'hasUnpaidInvoices': hasUnpaidInvoices,
      'invoiceCount': invoiceCount,
      'estimateCount': estimateCount,
    };
  }

  /// Create a copy with optional field overrides
  JobSummary copyWith({
    String? id,
    String? title,
    String? customerName,
    String? address,
    DateTime? created,
    DateTime? updated,
    String? status,
    double? totalAmount,
    bool? hasUnpaidInvoices,
    int? invoiceCount,
    int? estimateCount,
  }) {
    return JobSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      customerName: customerName ?? this.customerName,
      address: address ?? this.address,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
      hasUnpaidInvoices: hasUnpaidInvoices ?? this.hasUnpaidInvoices,
      invoiceCount: invoiceCount ?? this.invoiceCount,
      estimateCount: estimateCount ?? this.estimateCount,
    );
  }

  @override
  String toString() => 'JobSummary($id: $title)';
}
