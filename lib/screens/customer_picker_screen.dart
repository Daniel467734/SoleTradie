import 'package:flutter/material.dart';
import '../models/customer.dart';

class CustomerPickerScreen extends StatelessWidget {
  final List<Customer> customers;

  const CustomerPickerScreen({super.key, required this.customers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Customer')),
      body: ListView(
        children: [
          ...customers.map((customer) => ListTile(
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
    );
  }
}