import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../screens/pricebook_extensive_screen.dart' as pb;

/// Shared pricebook service - ensures all screens use the same data
class SharedPriceBookService {
  static const String _fileName = 'price_book.json';
  
  /// Load pricebook items from local storage (used by all screens)
  static Future<List<pb.PriceBookItem>> loadPriceBook() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      
      print('📚 SharedPriceBookService: Loading from ${file.path}');
      
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final fileSize = await file.length();
        
        print('📄 File found: size=${fileSize} bytes');
        
        if (jsonString.trim().isNotEmpty) {
          final jsonData = jsonDecode(jsonString);
          
          final List<dynamic> itemsList;
          if (jsonData is Map && jsonData.containsKey('items')) {
            itemsList = jsonData['items'] as List<dynamic>;
          } else {
            itemsList = jsonData as List<dynamic>;
          }
          
          final items = itemsList.map((e) => pb.PriceBookItem.fromJson(e)).toList();
          print('✅ SharedPriceBookService: Loaded ${items.length} items');
          return items;
        }
      }
      
      print('📄 SharedPriceBookService: No local file found');
      return [];
    } catch (e) {
      print('❌ SharedPriceBookService error: $e');
      return [];
    }
  }
  
  /// Get just the count (for quick status checks)
  static Future<int> getItemCount() async {
    final items = await loadPriceBook();
    return items.length;
  }
  
  /// Check if pricebook exists and has items
  static Future<bool> hasPriceBookData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      
      if (await file.exists()) {
        final fileSize = await file.length();
        return fileSize > 0;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}