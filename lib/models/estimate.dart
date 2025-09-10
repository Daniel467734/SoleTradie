// Define the Invoice class if it does not exist
class Invoice {
  // Add an id field to uniquely identify each invoice
  final String id;
  final double total;
  final bool isPaid;
  final DateTime? dueDate;
  // Add other fields as needed
  final String customerId;
  final String customerName;

  Invoice({
    required this.id,
    required this.total,
    required this.isPaid,
    this.dueDate,
    // Add other fields as needed
    required this.customerId,
    required this.customerName,
  });

  Invoice copyWith({
    String? id,
    double? total,
    bool? isPaid,
    DateTime? dueDate,
    // Add other fields as needed
    String? customerId,
    String? customerName,
  }) {
    return Invoice(
      id: id ?? this.id,
      total: total ?? this.total,
      isPaid: isPaid ?? this.isPaid,
      dueDate: dueDate ?? this.dueDate,
      // Add other fields as needed
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
    );
  }
}

final invoice = Invoice(
  id: 'inv-001',
  total: 100.0,
  isPaid: false, // <-- Always provide this value
  dueDate: DateTime.now().add(const Duration(days: 7)),
  customerId: 'cust-001',
  customerName: 'John Doe',
);

// Define the Estimate class
class Estimate {
  final String customerId;
  final String customerName;
  final String jobId;
  final String jobTitle;
  final String jobType;
  // ...other fields...

  Estimate({
    required this.customerId,
    required this.customerName,
    required this.jobId,
    required this.jobTitle,
    required this.jobType,
    // ...other fields...
  });

  // ...other methods...
}
