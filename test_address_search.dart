import 'package:flutter/material.dart';
import 'lib/widgets/address_search_field.dart';
import 'lib/services/address_search_service.dart';

void main() {
  runApp(AddressSearchTestApp());
}

class AddressSearchTestApp extends StatelessWidget {
  const AddressSearchTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Address Search Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AddressSearchTestScreen(),
    );
  }
}

class AddressSearchTestScreen extends StatefulWidget {
  const AddressSearchTestScreen({super.key});

  @override
  State<AddressSearchTestScreen> createState() => _AddressSearchTestScreenState();
}

class _AddressSearchTestScreenState extends State<AddressSearchTestScreen> {
  final _addressController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  AddressSearchResult? _selectedAddress;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Address Search Feature'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '✅ Address Search API Integration',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              
              const Text(
                'Enhanced Customer & Job Creation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              
              const Text(
                'Address search using free APIs (Nominatim for OpenStreetMap) with smart suggestions and geocoding.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Address Search Field
              AddressSearchField(
                controller: _addressController,
                labelText: 'Customer Address *',
                helperText: 'Start typing to search for addresses...',
                isRequired: true,
                onAddressSelected: (addressResult) {
                  setState(() {
                    _selectedAddress = addressResult;
                  });
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Address selected: ${addressResult.address}'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Selected Address Info
              if (_selectedAddress != null) ...[
                const Text(
                  'Selected Address Details:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Address: ${_selectedAddress!.address}'),
                      const SizedBox(height: 4),
                      Text('Latitude: ${_selectedAddress!.latitude?.toStringAsFixed(6) ?? 'N/A'}'),
                      Text('Longitude: ${_selectedAddress!.longitude?.toStringAsFixed(6) ?? 'N/A'}'),
                      if (_selectedAddress!.city != null)
                        Text('City: ${_selectedAddress!.city}'),
                      if (_selectedAddress!.region != null)
                        Text('Region: ${_selectedAddress!.region}'),
                      if (_selectedAddress!.postcode != null)
                        Text('Postcode: ${_selectedAddress!.postcode}'),
                      if (_selectedAddress!.country != null)
                        Text('Country: ${_selectedAddress!.country}'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              const Spacer(),

              // Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Features:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('• Real-time address suggestions'),
                    Text('• Free APIs (no API keys required)'),
                    Text('• Automatic geocoding (lat/lng)'),
                    Text('• Improved GPS tracking accuracy'),
                    Text('• Better timeline search functionality'),
                    Text('• Enhanced customer data quality'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
