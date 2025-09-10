import 'package:flutter/material.dart';
import 'lib/services/gps_service.dart';
import 'lib/screens/pricebook_screen.dart'; // For PriceBookItem

/// Demo app to test GPS service functionality
class GpsServiceDemo extends StatelessWidget {
  const GpsServiceDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Service Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const GpsTestScreen(),
    );
  }
}

class GpsTestScreen extends StatelessWidget {
  const GpsTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Service Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'GPS Site Visit Tracking Demo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => _testGpsService(context),
              icon: const Icon(Icons.gps_fixed),
              label: const Text('Open GPS Site History'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Features:\n'
                '• View GPS site visit history\n'
                '• Adjust distance range (5-100m)\n'
                '• Track time with ±0.5 hour increments\n'
                '• Automatic labour item creation\n'
                '• CAL pricebook integration',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _testGpsService(BuildContext context) {
    // Mock data for testing
    final mockPriceBook = <PriceBookItem>[
      PriceBookItem(
        code: 'CAL',
        name: 'Carpenter Allowance Labour',
        unit: 'hrs',
        groupCode: 'LABOUR',
        price: 65.0,
        purchasePrice: 0.0,
      ),
    ];

    GpsService.showGpsSiteHistoryWithLocation(
      context,
      '123 Test Street, Test City', // jobAddress
      'test-job-123', // jobId
      mockPriceBook, // priceBook
      (labourItem) {
        // Mock callback for adding labour items
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Labour Item Created:\n'
              'Description: ${labourItem.description}\n'
              'Quantity: ${labourItem.quantity.toStringAsFixed(1)}\n'
              'Rate: \$${labourItem.unitPrice.toStringAsFixed(2)}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      (sectionName) => 'Labour', // getOrCreateLabourSection
    );
  }
}

void main() {
  runApp(const GpsServiceDemo());
}
