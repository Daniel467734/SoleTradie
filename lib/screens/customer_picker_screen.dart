import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/demo_mode_service.dart';

class CustomerPickerScreen extends StatefulWidget {
  final List<Customer> customers;

  const CustomerPickerScreen({super.key, required this.customers});

  @override
  State<CustomerPickerScreen> createState() => _CustomerPickerScreenState();
}

class _CustomerPickerScreenState extends State<CustomerPickerScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDemoMode = DemoModeService.instance.isDemoMode;

    // In demo mode, searching for a name that doesn't exist "magically"
    // fabricates a new fake customer on the fly (see
    // DemoModeService.searchCustomers), so results always come from the
    // demo service's in-memory book instead of the real customers list.
    final List<Customer> results = isDemoMode
        ? DemoModeService.instance.searchCustomers(_search)
        : widget.customers.where((c) {
            if (_search.trim().isEmpty) return true;
            final lower = _search.toLowerCase();
            return c.name.toLowerCase().contains(lower) ||
                c.address.toLowerCase().contains(lower) ||
                c.email.toLowerCase().contains(lower);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(isDemoMode ? 'Select Customer (Demo Mode)' : 'Select Customer'),
        backgroundColor: isDemoMode ? Colors.deepPurple : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Search customers',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _search = val),
            ),
          ),
          if (isDemoMode)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Tip: type a full name that doesn't exist yet (e.g. \"Jenny Rodgers\") and it'll magically appear!",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                ...results.map((customer) => ListTile(
                      title: Text(customer.name),
                      subtitle: Text(customer.address),
                      onTap: () => Navigator.pop(context, customer),
                    )),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add New Customer'),
                  onTap: () async {
                    // Show dialog or navigate to add customer screen
                    // After adding, pop with the new customer
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}