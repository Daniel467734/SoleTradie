import 'package:flutter/material.dart';
import 'lib/templates/pdf_receipt_templates.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mitre 10 Template Test',
      home: Mitre10TestScreen(),
    );
  }
}

class Mitre10TestScreen extends StatefulWidget {
  const Mitre10TestScreen({super.key});

  @override
  Mitre10TestScreenState createState() => Mitre10TestScreenState();
}

class Mitre10TestScreenState extends State<Mitre10TestScreen> {
  String _extractedText = '';
  bool _isLoading = false;

  void _testMitre10Template() async {
    setState(() {
      _isLoading = true;
    });

    // Example Mitre 10 receipt text that would be extracted from PDF
    String sampleReceiptText = '''
    MITRE 10 NORTH CITY
    STORE 102
    
    Item ID: PAI-301
    PAINT BRUSH 2" FLAT
    Sale Price: \$15.95
    Discount: 10%
    Purchase Price: \$14.36
    
    Item ID: SCR-450
    SCREWS PHILLIPS 8G X 50MM
    Sale Price: \$8.50
    No Discount
    Purchase Price: \$8.50
    
    Item ID: TIM-200
    TIMBER PINE 90X45X2400
    Sale Price: \$12.90
    Discount: 15%
    Purchase Price: \$10.97
    
    ----------------------------------------
    SUBTOTAL: \$37.83
    GST: \$3.78
    TOTAL: \$41.61
    ''';

    try {
      final template = Mitre10Template();
      final result = await template.analyzeReceiptText(sampleReceiptText);
      
      setState(() {
        _extractedText = result.toString();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _extractedText = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mitre 10 Template Test'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mitre 10 Receipt Processing Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This test demonstrates how the Mitre 10 template extracts:',
                      style: TextStyle(fontSize: 14),
                    ),
                    SizedBox(height: 8),
                    Text('• Item ID codes (e.g., PAI-301, SCR-450)'),
                    Text('• Sale prices'),
                    Text('• Discount percentages'),
                    Text('• Purchase prices (calculated from discount)'),
                    Text('• Horizontal line items'),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testMitre10Template,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Processing...'),
                      ],
                    )
                  : Text('Test Mitre 10 Template'),
            ),
            SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Extracted Data:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              _extractedText.isEmpty
                                  ? 'No data extracted yet. Click the button above to test.'
                                  : _extractedText,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
