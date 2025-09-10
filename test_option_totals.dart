import 'package:flutter/material.dart';

void main() {
  runApp(const OptionTotalsDemo());
}

class OptionTotalsDemo extends StatelessWidget {
  const OptionTotalsDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Option Subsection Totals Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const OptionTotalsDemoScreen(),
    );
  }
}

class OptionTotalsDemoScreen extends StatefulWidget {
  const OptionTotalsDemoScreen({super.key});

  @override
  State<OptionTotalsDemoScreen> createState() => _OptionTotalsDemoScreenState();
}

class _OptionTotalsDemoScreenState extends State<OptionTotalsDemoScreen> {
  bool isGstRegistered = true;
  
  // Sample option subsections with items
  final List<OptionSubsection> optionSubsections = [
    OptionSubsection(
      name: 'Kitchen Upgrade',
      items: [
        EstimateItem(name: 'LED Downlights x8', quantity: 8, unitPrice: 45.00, purchasePrice: 25.00),
        EstimateItem(name: 'Under Cabinet Lighting', quantity: 1, unitPrice: 120.00, purchasePrice: 60.00),
        EstimateItem(name: 'Installation Labour', quantity: 4, unitPrice: 90.00, purchasePrice: 0.00),
      ],
    ),
    OptionSubsection(
      name: 'Bathroom Extra',
      items: [
        EstimateItem(name: 'Heat Lamp', quantity: 1, unitPrice: 180.00, purchasePrice: 95.00),
        EstimateItem(name: 'Exhaust Fan', quantity: 1, unitPrice: 220.00, purchasePrice: 120.00),
        EstimateItem(name: 'Wiring & Installation', quantity: 3, unitPrice: 90.00, purchasePrice: 0.00),
      ],
    ),
    OptionSubsection(
      name: 'Security System',
      items: [
        EstimateItem(name: 'CCTV Camera', quantity: 4, unitPrice: 250.00, purchasePrice: 150.00),
        EstimateItem(name: 'DVR System', quantity: 1, unitPrice: 400.00, purchasePrice: 220.00),
        EstimateItem(name: 'Cabling & Setup', quantity: 6, unitPrice: 90.00, purchasePrice: 0.00),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Option Subsection Totals'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          Row(
            children: [
              const Text('GST Registered:', style: TextStyle(fontSize: 16)),
              Switch(
                value: isGstRegistered,
                onChanged: (value) => setState(() => isGstRegistered = value),
                activeThumbColor: Colors.white,
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Feature: Option Subsection Totals',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Each option subsection now shows its own totals:',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Subtotal (ex GST) ${isGstRegistered ? '- shown when GST registered' : '- hidden when not GST registered'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      '• GST (15%) ${isGstRegistered ? '- shown when GST registered' : '- hidden when not GST registered'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      '• Total ${isGstRegistered ? '(inc GST)' : '(no GST)'} - always shown',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Text(
                      '• Total Profit - shown when profit view is enabled',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Option Sections',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...optionSubsections.map((subsection) => Column(
              children: [
                _buildSubsectionCard(subsection),
                _buildSubsectionTotals(subsection),
                const SizedBox(height: 16),
              ],
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSubsectionCard(OptionSubsection subsection) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subsection.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...subsection.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('${item.name} (${item.quantity})'),
                  ),
                  Text(
                    '\$${(item.unitPrice * item.quantity).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSubsectionTotals(OptionSubsection subsection) {
    final subtotal = subsection.items.fold<double>(0, (sum, item) => sum + (item.unitPrice * item.quantity));
    final gst = subtotal * 0.15;
    final total = isGstRegistered ? subtotal + gst : subtotal;
    final profit = subsection.items.fold<double>(0, (sum, item) => sum + ((item.unitPrice - item.purchasePrice) * item.quantity));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: Colors.yellow[50],
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                subsection.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              if (isGstRegistered)
                Text(
                  'Subtotal (ex GST): \$${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14),
                ),
              if (isGstRegistered)
                Text(
                  'GST (15%): \$${gst.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14),
                ),
              Text(
                isGstRegistered 
                    ? 'Total (inc GST): \$${total.toStringAsFixed(2)}'
                    : 'Total: \$${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                'Total Profit: \$${profit.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OptionSubsection {
  final String name;
  final List<EstimateItem> items;

  OptionSubsection({required this.name, required this.items});
}

class EstimateItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double purchasePrice;

  EstimateItem({
    required this.name,
    required this.quantity, 
    required this.unitPrice,
    required this.purchasePrice,
  });
}
