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
  final double? originalEstimateQuantity;
  final double? purchasePrice;
  final String section;
  final double? discountAmount;   // <-- Add this
  final double? discountPercent;  // <-- Add this

  EstimateItem({
    required this.name,
    required this.description,
    required this.unitPrice,
    required this.quantity,
    this.originalEstimateQuantity,
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
    double? originalEstimateQuantity,
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
      originalEstimateQuantity:
          originalEstimateQuantity ?? this.originalEstimateQuantity,
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
    'originalEstimateQuantity': originalEstimateQuantity,
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
    originalEstimateQuantity: json['originalEstimateQuantity'] != null
        ? (json['originalEstimateQuantity'] as num).toDouble()
        : null,
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


