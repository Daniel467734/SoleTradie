class BankTransaction {
  final String id;
  final DateTime date;
  final String description;
  final double amount;
  final double? balance;
  final String? reference;
  final String? category;
  bool isReconciled;
  String? matchedInvoiceId;

  BankTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.balance,
    this.reference,
    this.category,
    this.isReconciled = false,
    this.matchedInvoiceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'description': description,
        'amount': amount,
        'balance': balance,
        'reference': reference,
        'category': category,
        'isReconciled': isReconciled,
        'matchedInvoiceId': matchedInvoiceId,
      };

  factory BankTransaction.fromJson(Map<String, dynamic> json) => BankTransaction(
        id: json['id'],
        date: DateTime.parse(json['date']),
        description: json['description'],
        amount: json['amount'].toDouble(),
        balance: json['balance']?.toDouble(),
        reference: json['reference'],
        category: json['category'],
        isReconciled: json['isReconciled'] ?? false,
        matchedInvoiceId: json['matchedInvoiceId'],
      );

  BankTransaction copyWith({
    String? id,
    DateTime? date,
    String? description,
    double? amount,
    double? balance,
    String? reference,
    String? category,
    bool? isReconciled,
    String? matchedInvoiceId,
  }) {
    return BankTransaction(
      id: id ?? this.id,
      date: date ?? this.date,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      balance: balance ?? this.balance,
      reference: reference ?? this.reference,
      category: category ?? this.category,
      isReconciled: isReconciled ?? this.isReconciled,
      matchedInvoiceId: matchedInvoiceId ?? this.matchedInvoiceId,
    );
  }
}

class TransactionMatch {
  final BankTransaction transaction;
  final InvoiceForMatching invoice;
  final double confidence;
  final MatchType matchType;
  bool isApproved;

  TransactionMatch({
    required this.transaction,
    required this.invoice,
    required this.confidence,
    required this.matchType,
    this.isApproved = false,
  });
}

enum MatchType {
  automatic, // High confidence, auto-applied
  suggested, // Medium confidence, requires approval
  manual,    // Low confidence or manually created
}

// Simplified invoice class for matching purposes
class InvoiceForMatching {
  final String id;
  final double total;
  bool isPaid;
  final DateTime? dueDate;
  final String customerName;

  InvoiceForMatching({
    required this.id,
    required this.total,
    required this.isPaid,
    this.dueDate,
    required this.customerName,
  });
}
