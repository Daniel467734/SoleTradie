import 'estimate_item.dart';

class EstimateVersion {
  String? id;
  String? type; // 'invoice', 'estimate', 'quote'
  String? invoiceNumber;      // <-- Add this line
  String? estimateNumber;     // <-- Add this line
  DateTime? dueDate;
  DateTime? expiryDate;
  double amount;
  double profit;
  bool isPaid;
  bool isVoided;
  bool isArchived;
  bool isConverted;
  List<String>? sections;
  List<EstimateItem> items;
  String? filePath;
  String? status; // e.g. 'in_progress', 'final'
  DateTime? timestamp;
  final String? documentNumber; // <-- Add this

  EstimateVersion({
    this.id,
    this.type,
    this.invoiceNumber,     // <-- Add this line
    this.estimateNumber,    // <-- Add this line
    this.dueDate,
    this.expiryDate,
    this.amount = 0.0,
    this.profit = 0.0,
    this.isPaid = false,
    this.isVoided = false,
    this.isArchived = false,
    this.isConverted = false,
    this.sections,
    required this.items,
    this.filePath,
    this.status,
    this.timestamp,
    this.documentNumber,
  });

  // Add fromJson/toJson if needed for persistence
  factory EstimateVersion.fromJson(Map<String, dynamic> json) => EstimateVersion(
        id: json['id'],
        type: json['type'],
        invoiceNumber: json['invoiceNumber'],     // <-- Add this line
        estimateNumber: json['estimateNumber'],   // <-- Add this line
        dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
        expiryDate: json['expiryDate'] != null ? DateTime.parse(json['expiryDate']) : null,
        amount: (json['amount'] ?? 0).toDouble(),
        profit: (json['profit'] ?? 0).toDouble(),
        isPaid: json['isPaid'] ?? false,
        isVoided: json['isVoided'] ?? false,
        isArchived: json['isArchived'] ?? false,
        isConverted: json['isConverted'] ?? false,
        sections: (json['sections'] as List?)?.map((e) => e.toString()).toList(),
        items: (json['items'] as List).map((e) => EstimateItem.fromJson(e)).toList(),
        filePath: json['filePath'],
        status: json['status'],
        timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : null,
        documentNumber: json['documentNumber'], // <-- Add this line
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'invoiceNumber': invoiceNumber,     // <-- Add this line
        'estimateNumber': estimateNumber,   // <-- Add this line
        'dueDate': dueDate?.toIso8601String(),
        'expiryDate': expiryDate?.toIso8601String(),
        'amount': amount,
        'profit': profit,
        'isPaid': isPaid,
        'isVoided': isVoided,
        'isArchived': isArchived,
        'isConverted': isConverted,
        'sections': sections,
        'items': items.map((e) => e.toJson()).toList(),
        'filePath': filePath,
        'status': status,
        'timestamp': timestamp?.toIso8601String(),
        'documentNumber': documentNumber, // <-- Add this line
      };
}

class EstimateJob {
  final String title;
  final List<EstimateVersion> estimateVersions;

  EstimateJob({
    required this.title,
    required this.estimateVersions,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'estimateVersions': estimateVersions.map((v) => v.toJson()).toList(),
  };

  factory EstimateJob.fromJson(Map<String, dynamic> json) => EstimateJob(
    title: json['title'],
    estimateVersions: (json['estimateVersions'] as List<dynamic>?)
        ?.map((v) => EstimateVersion.fromJson(v))
        .toList() ?? [],
  );
}