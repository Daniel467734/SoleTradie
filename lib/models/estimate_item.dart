class Job {
  // Other properties...

  final String customerName;
  final List<EstimateItem> estimateItems;
  final DateTime? created;

  Job({
    // Other parameters...
    required this.customerName,
    required this.estimateItems,
    this.created,
  });

  // Other methods...
}

class EstimateItem {
  final String name;
  final String description;
  final double unitPrice;
  final double quantity;
  final double? purchasePrice;
  final String section;
  final double? discountAmount;   // <-- Add this
  final double? discountPercent;  // <-- Add this

  EstimateItem({
    required this.name,
    required this.description,
    required this.unitPrice,
    required this.quantity,
    this.purchasePrice,
    required this.section,
    this.discountAmount,   // <-- Add this
    this.discountPercent,  // <-- Add this
  });

  double get total => unitPrice * quantity;

  EstimateItem copyWith({
    String? name,
    String? description,
    double? unitPrice,
    double? quantity,
    double? purchasePrice,
    String? section,
    double? discountAmount,   // <-- Add this
    double? discountPercent,  // <-- Add this
  }) {
    return EstimateItem(
      name: name ?? this.name,
      description: description ?? this.description,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      section: section ?? this.section,
      discountAmount: discountAmount ?? this.discountAmount,     // <-- Add this
      discountPercent: discountPercent ?? this.discountPercent,  // <-- Add this
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'purchasePrice': purchasePrice,
    'section': section,
    'discountAmount': discountAmount,     // <-- Add this
    'discountPercent': discountPercent,   // <-- Add this
  };

  factory EstimateItem.fromJson(Map<String, dynamic> json) => EstimateItem(
    name: json['name'],
    description: json['description'],
    unitPrice: (json['unitPrice'] as num).toDouble(),
    quantity: (json['quantity'] as num).toDouble(),
    purchasePrice: json['purchasePrice'] != null ? (json['purchasePrice'] as num).toDouble() : null,
    section: json['section'],
    discountAmount: json['discountAmount'] != null ? (json['discountAmount'] as num).toDouble() : null,     // <-- Add this
    discountPercent: json['discountPercent'] != null ? (json['discountPercent'] as num).toDouble() : null,  // <-- Add this
  );
}

extension JobSearch on List<Job> {
  List<Job> search(String search) {
    if (search.isEmpty) return this;

    return where((job) {
      return job.customerName.toLowerCase().contains(search.toLowerCase());
    }).toList()
      ..sort((a, b) => (b.created ?? DateTime(1970)).compareTo(a.created ?? DateTime(1970)));
  }
}


