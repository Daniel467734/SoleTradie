class InvoicePayment {
  final double amount;
  final DateTime date;
  final String? note;

  InvoicePayment({
    required this.amount,
    required this.date,
    this.note,
  });

  factory InvoicePayment.fromJson(Map<String, dynamic> json) => InvoicePayment(
        amount: (json['amount'] ?? 0).toDouble(),
        date: DateTime.parse(json['date'] as String),
        note: json['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      };
}

// Define the Invoice class if it does not exist
class Invoice {
  // Add an id field to uniquely identify each invoice
  final String id;
  final double total;
  final double amount; // Add amount property for compatibility
  final double amountPaid;
  final List<InvoicePayment> payments;
  bool isPaid;
  DateTime? dueDate;
  // Add other fields as needed
  final String customerId;
  final String customerName;
  final String status; // e.g. 'unpaid', 'sent', 'paid'
  bool emailSent; // <-- Add this line
  bool isArchived; // Add this for compatibility
  final String? filePath; // Add filePath property for PDF storage

  /// How this invoice was marked paid: 'manual' (marked paid by hand in
  /// the app - e.g. cash/EFT the user has confirmed themselves) or
  /// 'xero' (reconciled automatically via Xero's bank feed webhook).
  /// Defaults to 'manual' since that's the original/most common path;
  /// set to 'xero' by `XeroInvoiceRepositoryImpl.reconcileFromWebhookEvent`.
  /// Purely informational (e.g. for display as "Marked Paid" vs "Paid"),
  /// doesn't affect `isPaid`/balance logic.
  String paidVia;

  double get balance => (total - amountPaid).clamp(0.0, double.infinity);

  Invoice({
    required this.id,
    required this.total,
    double? amount,
    this.amountPaid = 0.0,
    List<InvoicePayment>? payments,
    this.isPaid = false,
    this.dueDate,
    // Add other fields as needed
    required this.customerId,
    required this.customerName,
    this.status = 'unpaid',
    this.emailSent = false, // <-- Add this default
    this.isArchived = false, // <-- Add this default
    this.filePath, // Add filePath parameter
    this.paidVia = 'manual',
  })  : amount = amount ?? total,
        payments = payments ?? [];

  Invoice copyWith({
    String? id,
    double? total,
    double? amount,
    double? amountPaid,
    List<InvoicePayment>? payments,
    bool? isPaid,
    DateTime? dueDate,
    // Add other fields as needed
    String? customerId,
    String? customerName,
    String? status,
    bool? emailSent,
    bool? isArchived,
    String? filePath,
    String? paidVia,
  }) {
    return Invoice(
      id: id ?? this.id,
      total: total ?? this.total,
      amount: amount ?? this.amount,
      amountPaid: amountPaid ?? this.amountPaid,
      payments: payments ?? this.payments,
      isPaid: isPaid ?? this.isPaid,
      dueDate: dueDate ?? this.dueDate,
      // Add other fields as needed
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      status: status ?? this.status,
      emailSent: emailSent ?? this.emailSent,
      isArchived: isArchived ?? this.isArchived,
      filePath: filePath ?? this.filePath,
      paidVia: paidVia ?? this.paidVia,
    );
  }

  Invoice addPayment(InvoicePayment payment) {
    final updatedAmountPaid = (amountPaid + payment.amount).clamp(0.0, amount);
    return copyWith(
      amountPaid: updatedAmountPaid,
      payments: [...payments, payment],
      isPaid: updatedAmountPaid >= amount,
      status: updatedAmountPaid >= amount ? 'paid' : status,
    );
  }

  // Update fromJson/toJson if needed:
  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: json['id'],
        total: (json['total'] ?? 0).toDouble(),
        amount: (json['amount'] ?? json['total'] ?? 0).toDouble(),
        amountPaid: (json['amountPaid'] ?? 0).toDouble(),
        payments: (json['payments'] as List<dynamic>?)
                ?.map((item) => InvoicePayment.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
        isPaid: json['isPaid'] ?? false,
        dueDate: json['dueDate'] != null ? DateTime.tryParse(json['dueDate']) : null,
        customerId: json['customerId'] ?? '',
        customerName: json['customerName'] ?? '',
        status: json['status'] ?? 'unpaid',
        emailSent: json['emailSent'] ?? false,
        isArchived: json['isArchived'] ?? false,
        filePath: json['filePath'],
        paidVia: json['paidVia'] ?? 'manual',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'total': total,
        'amount': amount,
        'amountPaid': amountPaid,
        'payments': payments.map((item) => item.toJson()).toList(),
        'isPaid': isPaid,
        'dueDate': dueDate?.toIso8601String(),
        'customerId': customerId,
        'customerName': customerName,
        'status': status,
        'emailSent': emailSent,
        'isArchived': isArchived,
        'filePath': filePath,
        'paidVia': paidVia,
      };
}

final invoice = Invoice(
  id: 'inv-001',
  total: 100.0,
  isPaid: false, // <-- Always provide this value
  dueDate: DateTime.now().add(const Duration(days: 7)),
  customerId: 'cust-001',
  customerName: 'John Doe',
  filePath: null, // Add filePath parameter
);

