import '../models/price_book_item.dart';

/// Simple adapter to convert between screen and service models
class PriceBookAdapter {
  /// Convert screen PriceBookItem to service PriceBookItem
  static PriceBookItem screenToService(dynamic screenItem) {
    // Handle the conversion based on available fields
    return PriceBookItem.fromJson({
      'code': screenItem.code ?? screenItem.id ?? '',
      'name': screenItem.name ?? '',
      'description': screenItem.description ?? '',
      'price': screenItem.price ?? screenItem.unitPrice ?? 0.0,
      'purchasePrice': screenItem.purchasePrice ?? 0.0,
      'groupCode': screenItem.groupCode ?? screenItem.category ?? 'General',
      'unit': screenItem.unit ?? 'each',
      'salePrice': screenItem.price ?? screenItem.unitPrice ?? 0.0,
    });
  }
  
  /// Convert service PriceBookItem to screen PriceBookItem format
  static Map<String, dynamic> serviceToScreenJson(PriceBookItem serviceItem) {
    return {
      'code': serviceItem.code,
      'name': serviceItem.name,
      'description': serviceItem.description,
      'price': serviceItem.price,
      'purchasePrice': serviceItem.purchasePrice,
      'groupCode': serviceItem.groupCode,
      'unit': serviceItem.unit,
      'favorite': false, // Default value
    };
  }
}