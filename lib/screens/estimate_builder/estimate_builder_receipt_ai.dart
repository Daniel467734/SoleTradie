part of '../estimate_builder_screen.dart';

extension _EstimateBuilderReceiptAiExt on _EstimateBuilderScreenState {
  Future<dynamic> _analyzeReceiptText(String text) async {
    final apiKey = await OpenAiKeyService.getKey();
    final prompt = '''
You are reading a JA Russell invoice. Extract all line items as a JSON array.
For each item, return:
- "id_number": the Stock code (e.g. "100010" or "Q5070535").
  **Never use the Bin column. Never use the Name/Description column as the ID code, even if it contains numbers or codes.
  The Stock code is always to the right of the Bin column and may be numeric or alphanumeric (e.g. "100010" or "Q5070535").
  Do not return "0" for id_number unless the stock code in the invoice is literally "0".**
- "item_name": the Name/Description (e.g. "1.5mm² TWIN & EARTH CABLE")
- "quantity": the Qty (as an integer)
- "net_price": the Net Price per unit (the purchase price from the "Net Price" column, as a decimal number)

Do NOT ignore the Net Price column - this is the purchase price and must be extracted accurately.

The Bin column is often the first column and may contain numbers or be blank. The Stock code is always the next column to the right of Bin and may be numeric or alphanumeric (e.g. "100010" or "Q5070535"). Do not use the Bin value as the Stock code.

Example input:
Bin  Stock code  Name/Description         Qty  Unit  B/ord  Price  Net Price  Extension
---  ----------  -----------------------  ---  ----  -----  -----  ---------  ---------
 12   100010      1.5mm² TWIN & EARTH CABLE  2   RL           45.00    45.00      90.00
      200020      10A SINGLE LIGHT SWITCH    5   EA           3.00     3.00       15.00

Example output:
[
  {"id_number": "100010", "item_name": "1.5mm² TWIN & EARTH CABLE", "quantity": 2, "net_price": 45.00},
  {"id_number": "200020", "item_name": "10A SINGLE LIGHT SWITCH", "quantity": 5, "net_price": 3.00}
]

If you can't find a code, quantity, or net_price, leave it blank or use 1 for quantity and 0 for net_price.

Now extract from this invoice text:
$text
''';

    _showAiProgressDialog('Sending receipt data to AI...');
    try {
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read items from receipt.')),
          );
          return null;
        }
      } else {
        String errorMessage = 'AI error (${response.statusCode})';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            final error = errorData['error'];
            if (error is Map && error.containsKey('message')) {
              errorMessage = error['message'] ?? errorMessage;
            }
          }
        } catch (_) {
          errorMessage = 'AI error: ${response.statusCode}';
        }

        debugPrint('❌ Receipt analysis failed: $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        throw Exception('Failed to analyze receipt: $errorMessage');
      }
    } catch (e) {
      debugPrint('❌ Receipt analysis error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
      rethrow;
    } finally {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Future<dynamic> _analyzeReceiptTextWithTemplate(
      String text, String templateName) async {
    String templatePrompt;
    try {
      final templateFile = await rootBundle.loadString(
          'assets/receipt_templates/${templateName.toLowerCase().replaceAll(' ', '_')}.txt');
      final templateData = jsonDecode(templateFile) as List;
      templatePrompt = templateData.first['prompt'] as String;
    } catch (e) {
      templatePrompt = '''
You are reading a receipt/invoice. Extract all line items as a JSON array.
For each item, return:
- "id_number": the product/stock code 
- "item_name": the item description/name
- "quantity": the quantity (as an integer)
- "net_price": the unit price (as a decimal number)

If you can't find a code, quantity, or net_price, leave it blank or use 1 for quantity and 0 for net_price.

Now extract from this invoice text:
''';
    }

    final apiKey = await OpenAiKeyService.getKey();
    final fullPrompt = templatePrompt.replaceAll(r'$text', text);

    _showAiProgressDialog('Sending receipt data to AI...');
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4',
          'messages': [
            {'role': 'user', 'content': fullPrompt}
          ],
          'max_tokens': 2000,
          'temperature': 0,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];

        try {
          final parsed = jsonDecode(content);
          return parsed;
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read items from receipt.')),
          );
          return null;
        }
      } else {
        String errorMessage = 'AI error (${response.statusCode})';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            final error = errorData['error'];
            if (error is Map && error.containsKey('message')) {
              errorMessage = error['message'] ?? errorMessage;
            }
          }
        } catch (_) {
          errorMessage = 'AI error: ${response.statusCode}';
        }

        debugPrint('❌ Template receipt analysis failed: $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        throw Exception('Failed to analyze receipt: $errorMessage');
      }
    } catch (e) {
      debugPrint('❌ Template receipt analysis error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
      rethrow;
    } finally {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }
}
