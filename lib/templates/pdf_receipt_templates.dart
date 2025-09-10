import 'dart:convert';
import 'package:http/http.dart' as http;

/// Abstract base class for PDF receipt templates
abstract class PdfReceiptTemplate {
  String get name;
  String get description;
  
  /// Analyzes receipt text and extracts line items
  Future<dynamic> analyzeReceiptText(String text);
}

/// JA Russell PDF receipt template
class JARussellTemplate extends PdfReceiptTemplate {
  @override
  String get name => 'JA Russell';
  
  @override
  String get description => 'Template for JA Russell electrical supplier invoices';
  
  @override
  Future<dynamic> analyzeReceiptText(String text) async {
    const apiKey = 'REDACTED_OPENAI_KEY';
    final prompt = '''
You are reading a JA Russell invoice. Extract all line items as a JSON array.
For each item, return:
- "id_number": the Stock code (e.g. "100010"). 
  **Never use the Bin column. Never use the Name/Description column as the ID code, even if it contains numbers or codes. 
  The Stock code is always to the right of the Bin column and is numeric.**
- "item_name": the Name/Description (e.g. "1.5mm² TWIN & EARTH CABLE")
- "quantity": the Qty (as an integer)
- "sale_price": the Price column value (what you would sell it for)
- "purchase_price": the Net Price column value (what you paid for it)

The Bin column is often the first column and may contain numbers or be blank. The Stock code is always the next column to the right of Bin and is numeric (e.g. "100010"). Do not use the Bin value as the Stock code.

Example input:
Bin  Stock code  Name/Description         Qty  Unit  B/ord  Price  Net Price  Extension
---  ----------  -----------------------  ---  ----  -----  -----  ---------  ---------
 12   100010      1.5mm² TWIN & EARTH CABLE  2   RL           45.00    45.00      90.00
      200020      10A SINGLE LIGHT SWITCH    5   EA           3.00     3.00       15.00

Example output:
[
  {"id_number": "100010", "item_name": "1.5mm² TWIN & EARTH CABLE", "quantity": 2, "sale_price": 45.00, "purchase_price": 45.00},
  {"id_number": "200020", "item_name": "10A SINGLE LIGHT SWITCH", "quantity": 5, "sale_price": 3.00, "purchase_price": 3.00}
]

If you can't find a code, quantity, or price, leave it blank or use 1 for quantity and 0 for prices.

Now extract from this invoice text:
$text
''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        "model": "gpt-3.5-turbo",
        "messages": [
          {"role": "user", "content": prompt}
        ],
        "max_tokens": 1000,
        "temperature": 0,
        "stop": ["]}"],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];
      try {
        final parsed = jsonDecode(content);
        return parsed;
      } catch (e) {
        throw Exception('Could not parse response from AI service');
      }
    } else {
      throw Exception('AI service error: ${response.body}');
    }
  }
}

/// Example of another template you could add
class BunningsTemplate extends PdfReceiptTemplate {
  @override
  String get name => 'Bunnings';
  
  @override
  String get description => 'Template for Bunnings Warehouse receipts';
  
  @override
  Future<dynamic> analyzeReceiptText(String text) async {
    // TODO: Implement Bunnings-specific parsing logic
    const apiKey = 'REDACTED_OPENAI_KEY';
    final prompt = '''
You are reading a Bunnings Warehouse receipt. Extract all line items as a JSON array.
For each item, return:
- "id_number": the article number or barcode
- "item_name": the product description
- "quantity": the quantity purchased

Now extract from this receipt text:
$text
''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        "model": "gpt-3.5-turbo",
        "messages": [
          {"role": "user", "content": prompt}
        ],
        "max_tokens": 1000,
        "temperature": 0,
        "stop": ["]}"],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];
      try {
        final parsed = jsonDecode(content);
        return parsed;
      } catch (e) {
        throw Exception('Could not parse response from AI service');
      }
    } else {
      throw Exception('AI service error: ${response.body}');
    }
  }
}

/// Mitre 10 template example
class Mitre10Template extends PdfReceiptTemplate {
  @override
  String get name => 'Mitre 10';
  
  @override
  String get description => 'Template for Mitre 10 hardware store receipts';
  
  @override
  Future<dynamic> analyzeReceiptText(String text) async {
    const apiKey = 'REDACTED_OPENAI_KEY';
    final prompt = '''
You are reading a Mitre 10 receipt. Extract all line items as a JSON array.
For each item, return:
- "id_number": the Item ID only (never use any other code like Auth or unique codes)
- "item_name": the Description/product name
- "quantity": the Qty value
- "sale_price": the Price value (before any discounts)
- "discount_percentage": the Discount percentage (if any)
- "purchase_price": calculated price after discount (sale_price - (sale_price * discount_percentage / 100))

Important notes:
- Item lines are horizontal
- Only use Item ID as the product code, ignore Auth codes or unique codes in description
- Ignore any "your unique code" text in description lines
- If there is a discount percentage, calculate the purchase price by subtracting the discount from sale price
- If no discount, purchase_price equals sale_price

Example calculation:
If Price is 100.00 and Discount is 10%, then:
purchase_price = 100.00 - (100.00 * 10 / 100) = 90.00

Now extract from this receipt text:
$text
''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        "model": "gpt-3.5-turbo",
        "messages": [
          {"role": "user", "content": prompt}
        ],
        "max_tokens": 1000,
        "temperature": 0,
        "stop": ["]}"],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];
      try {
        final parsed = jsonDecode(content);
        return parsed;
      } catch (e) {
        throw Exception('Could not parse response from AI service');
      }
    } else {
      throw Exception('AI service error: ${response.body}');
    }
  }
}

/// Template registry for managing all available templates
class PdfReceiptTemplateRegistry {
  static final List<PdfReceiptTemplate> _templates = [
    JARussellTemplate(),
    BunningsTemplate(),
    Mitre10Template(),
    // Add more templates here as needed
  ];
  
  /// Get all available templates
  static List<PdfReceiptTemplate> get templates => List.unmodifiable(_templates);
  
  /// Get template by name
  static PdfReceiptTemplate? getTemplate(String name) {
    try {
      return _templates.firstWhere((template) => template.name == name);
    } catch (e) {
      return null;
    }
  }
  
  /// Get default template (JA Russell for now)
  static PdfReceiptTemplate get defaultTemplate => _templates.first;
}
