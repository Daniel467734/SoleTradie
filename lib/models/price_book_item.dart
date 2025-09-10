import 'package:isar/isar.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

part 'price_book_item.g.dart';

@collection
class PriceBookItem {
  Id? id;
  
  @Index()
  late String code;
  
  late String name;
  late String? category;
  late double purchasePrice;
  late double salePrice;
  late double? markupPercent;
  late String? unit;
  late String? description;
  
  // Additional compatibility fields for old pricebook screen
  late bool favorite;
  late bool markupOverridden;
  late String? origin;
  late int usageCount;
  late double percentageChanged;
  
  @Index()
  late DateTime createdAt;
  late DateTime updatedAt;
  
  // Sync fields
  late bool isDeleted;
  late bool needsSync;
  late String? cloudId; // Firestore document ID
  
  PriceBookItem({
    this.code = '',
    this.name = '',
    this.category,
    this.purchasePrice = 0.0,
    this.salePrice = 0.0,
    this.markupPercent,
    this.unit,
    this.description,
    this.favorite = false,
    this.markupOverridden = false,
    this.origin,
    this.usageCount = 0,
    this.percentageChanged = 0.0,
    this.isDeleted = false,
    this.needsSync = true,
    this.cloudId,
  }) {
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
  
  // Firestore compatibility
  Map<String, dynamic> toFirestore() {
    return {
      'code': code,
      'name': name,
      'category': category,
      'groupCode': category, // Add for compatibility
      'purchasePrice': purchasePrice,
      'salePrice': salePrice,
      'price': salePrice, // Add for compatibility
      'markupPercent': markupPercent,
      'unit': unit,
      'description': description,
      'favorite': favorite,
      'markupOverridden': markupOverridden,
      'origin': origin,
      'usageCount': usageCount,
      'percentageChanged': percentageChanged,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }
  
  // Add toJson for serialization
  Map<String, dynamic> toJson() => toFirestore();
  
  // Compatibility method for old pricebook screen
  factory PriceBookItem.fromJson(Map<String, dynamic> json) {
    return PriceBookItem(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? json['groupCode'], // Handle both field names
      purchasePrice: (json['purchasePrice'] ?? 0.0).toDouble(),
      salePrice: (json['salePrice'] ?? json['price'] ?? 0.0).toDouble(),
      markupPercent: json['markupPercent']?.toDouble(),
      unit: json['unit'],
      description: json['description'],
      favorite: json['favorite'] ?? false,
      markupOverridden: json['markupOverridden'] ?? false,
      origin: json['origin'],
      usageCount: json['usageCount'] ?? 0,
      percentageChanged: (json['percentageChanged'] ?? 0.0).toDouble(),
      isDeleted: json['isDeleted'] ?? false,
      needsSync: false,
      cloudId: json['cloudId'],
    )
      ..createdAt = _parseDateTime(json['createdAt'])
      ..updatedAt = _parseDateTime(json['updatedAt']);
  }
  
  // Helper method to parse DateTime from various sources (String, Timestamp, etc.)
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    
    if (value is DateTime) return value;
    
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    
    // Handle Firestore Timestamp
    if (value is firestore.Timestamp) {
      try {
        return value.toDate();
      } catch (e) {
        return DateTime.now();
      }
    }
    
    return DateTime.now();
  }
  
  // Compatibility getter for old pricebook screen
  double get price => salePrice;
  set price(double value) => salePrice = value;
  
  // Compatibility getter for groupCode
  String? get groupCode => category;
  set groupCode(String? value) => category = value;
  
  factory PriceBookItem.fromFirestore(Map<String, dynamic> data, String docId) {
    return PriceBookItem(
      code: data['code'] ?? '',
      name: data['name'] ?? '',
      category: data['category'],
      purchasePrice: (data['purchasePrice'] ?? 0.0).toDouble(),
      salePrice: (data['salePrice'] ?? 0.0).toDouble(),
      markupPercent: data['markupPercent']?.toDouble(),
      unit: data['unit'],
      description: data['description'],
      isDeleted: data['isDeleted'] ?? false,
      needsSync: false,
      cloudId: docId,
    )
      ..createdAt = _parseDateTime(data['createdAt'])
      ..updatedAt = _parseDateTime(data['updatedAt']);
  }
}
