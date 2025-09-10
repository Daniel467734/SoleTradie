import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'settings_screen.dart';
import 'home_dashboard.dart';
import '../models/customer.dart';
import '../models/estimate_template.dart'; // <-- Use the real model

class JobDashboardScreen extends StatefulWidget {
  const JobDashboardScreen({super.key});

  @override
  State<JobDashboardScreen> createState() => _JobDashboardScreenState();
}

class _JobDashboardScreenState extends State<JobDashboardScreen> {
  List<Customer> customers = [];

  Future<void> _createAndOpenPdf(BuildContext context) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Center(
          child: pw.Text('Hello, this is your certificate!'),
        ),
      ),
    );
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/certificate.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);
  }

  Future<void> _showTemplatePicker(BuildContext context) async {
    final templates = await loadTemplates();
    await showTemplatePickerDialog(context, templates);
  }

  // Replace dummy implementation with a real or empty list for now
  Future<List<EstimateTemplate>> loadTemplates() async {
    // TODO: Load from disk or your real data source
    await Future.delayed(const Duration(milliseconds: 500));
    return []; // Return an empty list or load real templates
  }

  void _showAddJobDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AddJobDialog(
        customers: customers,
        onCustomerAdded: (customer) {
          _addCustomer(customer);
        },
      ),
    );
  }

  void _showAddCustomerDialog() async {
    final companyController = TextEditingController();
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final paymentTermsOptions = [
      '7 days',
      '14 days',
      '21 days',
      '20th of this month',
      '20th of next month',
    ];
    String selectedPaymentTerm = '7 days';

    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: companyController,
                  decoration: const InputDecoration(labelText: 'Company Name (if applicable)'),
                ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedPaymentTerm,
                  decoration: const InputDecoration(labelText: 'Payment Terms'),
                  items: paymentTermsOptions
                      .map((term) => DropdownMenuItem(
                            value: term,
                            child: Text(term),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedPaymentTerm = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // At least one of company or name required
                if (companyController.text.trim().isEmpty && nameController.text.trim().isEmpty) return;
                final newCustomer = Customer(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  companyName: companyController.text.trim(),
                  address: addressController.text.trim(),
                  email: emailController.text.trim(),
                  phone: phoneController.text.trim(),
                  paymentTerms: selectedPaymentTerm,
                );
                Navigator.pop(context, newCustomer);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        customers.add(result);
      });
      saveCustomersToDisk();
    }
  }

  Future<void> saveCustomersToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = customers.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList('customer_book', jsonList);
  }

  Future<void> loadCustomersFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('customer_book') ?? [];
    setState(() {
      customers = jsonList.map((s) => Customer.fromJson(jsonDecode(s))).toList();
    });
  }

  // Add a customer
  void _addCustomer(Customer customer) {
    setState(() {
      customers.add(customer);
    });
    saveCustomersToDisk();
  }

  // Edit a customer
  void _editCustomer(Customer updated) {
    setState(() {
      final idx = customers.indexWhere((c) => c.id == updated.id);
      if (idx != -1) customers[idx] = updated;
    });
    saveCustomersToDisk();
  }

  // Remove a customer
  void _removeCustomer(String id) {
    setState(() {
      customers.removeWhere((c) => c.id == id);
    });
    saveCustomersToDisk();
  }

  @override
  void initState() {
    super.initState();
    loadCustomersFromDisk();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.home),
              label: const Text('Home'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomeDashboard()),
                );
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Invoices Due'),
              onPressed: () {
                // TODO: Navigate to your Invoices Due page
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Settings'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Create & Open Certificate PDF'),
              onPressed: () => _createAndOpenPdf(context),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.description),
              label: const Text('Select Template'),
              onPressed: () => _showTemplatePicker(context),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Job'),
              onPressed: _showAddJobDialog,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add Customer'),
              onPressed: _showAddCustomerDialog,
            ),
            const SizedBox(height: 32),
            // Add more job-related actions here
            const Text(
              'Your jobs will be listed here...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

Future<EstimateTemplate?> showTemplatePickerDialog(BuildContext context, List<EstimateTemplate> templates) async {
  return showDialog<EstimateTemplate>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Select Estimate Template'),
        content: SizedBox(
          width: double.maxFinite,
          child: templates.isEmpty
              ? const Text('No templates found.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return ListTile(
                      title: Text(template.name ?? 'Template ${index + 1}'),
                      onTap: () => Navigator.pop(context, template),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}

class AddJobDialog extends StatefulWidget {
  final List<Customer> customers;
  final void Function(Customer)? onCustomerAdded;

  const AddJobDialog({
    super.key,
    required this.customers,
    required this.onCustomerAdded,
  });

  @override
  _AddJobDialogState createState() => _AddJobDialogState();
}

class _AddJobDialogState extends State<AddJobDialog> {
  String search = '';
  Customer? selectedCustomer;

  void _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) return;
              final newCustomer = Customer(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameController.text.trim(),
                address: addressController.text.trim(),
                email: emailController.text.trim(),
                phone: phoneController.text.trim(),
              );
              Navigator.pop(context, newCustomer);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      widget.onCustomerAdded?.call(result);
      setState(() {
        selectedCustomer = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = widget.customers.where((c) =>
      c.name.toLowerCase().contains(search.toLowerCase()) ||
      c.address.toLowerCase().contains(search.toLowerCase()) ||
      c.email.toLowerCase().contains(search.toLowerCase())
    ).toList();

    return AlertDialog(
      title: const Text('Add Job'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Search customer'),
            onChanged: (val) => setState(() => search = val),
          ),
          SizedBox(
            height: 200,
            child: filteredCustomers.isEmpty
                ? const Center(child: Text('No customers found.'))
                : ListView.builder(
                    itemCount: filteredCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = filteredCustomers[index];
                      final isSelected = customer == selectedCustomer;
                      return Card(
                        color: isSelected ? Colors.blue.shade50 : null,
                        child: ListTile(
                          title: Text(customer.name),
                          subtitle: Text(customer.address),
                          onTap: () => setState(() => selectedCustomer = customer),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: Colors.blue)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Add New Customer'),
            onPressed: _showAddCustomerDialog,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: selectedCustomer == null
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JobDetailsEntryScreen(customer: selectedCustomer!),
                    ),
                  );
                },
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class JobDetailsEntryScreen extends StatefulWidget {
  final Customer customer;
  const JobDetailsEntryScreen({required this.customer, super.key});

  @override
  State<JobDetailsEntryScreen> createState() => _JobDetailsEntryScreenState();
}

class _JobDetailsEntryScreenState extends State<JobDetailsEntryScreen> {
  late TextEditingController addressController;

  @override
  void initState() {
    super.initState();
    // Default to customer address, but editable
    addressController = TextEditingController(text: widget.customer.address);
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use widget.customer for all customer info
    return Scaffold(
      appBar: AppBar(title: Text('Job for ${widget.customer.name}')),
      body: Column(
        children: [
          TextField(
            controller: addressController,
            decoration: const InputDecoration(labelText: 'Job Address'),
          ),
          // ...other fields...
        ],
      ),
    );
  }
}