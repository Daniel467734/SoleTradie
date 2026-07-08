import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_screen.dart';
import '../models/customer.dart';
import 'package:url_launcher/url_launcher.dart';

class Invoice {
  final double total;
  final bool isPaid;
  final String description; // Add a description for display

  Invoice({required this.total, required this.isPaid, required this.description});
}

double calculateTotalInvoiceDue(List<Invoice> invoices) {
  return invoices
      .where((invoice) => !invoice.isPaid)
      .fold(0.0, (sum, invoice) => sum + invoice.total);
}

// Example invoice list
final invoices = [
  Invoice(total: 1200.0, isPaid: false, description: 'Invoice #1001'),
  Invoice(total: 800.0, isPaid: true, description: 'Invoice #1002'),
  Invoice(total: 500.0, isPaid: false, description: 'Invoice #1003'),
];

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  List<Customer> customers = [];
  late List<Invoice> _invoices;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _invoices = List.from(invoices);
  }

  Future<void> _saveCustomers() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/customers.json');
    final jsonList = customers.map((c) => c.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  Future<void> _loadCustomers() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/customers.json');
    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        customers = jsonList.map((e) => Customer.fromJson(e)).toList();
      });
    }
  }

  void _addCustomer(Customer customer) {
    setState(() {
      customers.add(customer);
    });
    _saveCustomers();
  }

  void updateCustomer(Customer updated) {
    setState(() {
      final idx = customers.indexWhere((c) => c.id == updated.id);
      if (idx != -1) customers[idx] = updated;
    });
    _saveCustomers();
  }

  void removeCustomer(String id) {
    setState(() {
      customers.removeWhere((c) => c.id == id);
    });
    _saveCustomers();
  }

  Future<void> _testWebUrl() async {
    final uri = Uri.parse('https://www.google.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the web URL.')),
      );
    }
  }

  Future<void> _confirmWipeJobData() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wipe Job Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This will delete all local job, estimate, quote, invoice, and in-progress build data. This cannot be undone.'),
            const SizedBox(height: 16),
            const Text('Type DELETE JOB DATA to confirm.'),
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Confirmation text',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (controller.text.trim() == 'DELETE JOB DATA') {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please type DELETE JOB DATA exactly to confirm.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _wipeJobData();
    }
  }

  Future<void> _wipeJobData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();

      final jobsFile = File('${directory.path}/jobs.json');
      if (await jobsFile.exists()) {
        await jobsFile.delete();
      }

      await for (final entity in directory.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('job_') && name.endsWith('.json')) {
            await entity.delete();
          }
        }
      }

      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('in_progress_builds_') ||
            key.startsWith('in_progress_estimate_') ||
            key == 'estimate_builds' ||
            key == 'quote_builds' ||
            key == 'invoice_builds') {
          await prefs.remove(key);
        }
      }

      setState(() {
        _invoices.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job, invoice, estimate and in-progress build data wiped.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to wipe job data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalInvoiceDue = calculateTotalInvoiceDue(_invoices);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Total Invoice Amount Due',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${totalInvoiceDue.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 32, color: Colors.indigo, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All Invoices',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _invoices.length,
                itemBuilder: (context, index) {
                  final invoice = _invoices[index];
                  return ListTile(
                    leading: Icon(
                      invoice.isPaid ? Icons.check_circle : Icons.warning,
                      color: invoice.isPaid ? Colors.green : Colors.red,
                    ),
                    title: Text(invoice.description),
                    subtitle: Text('Amount: \$${invoice.total.toStringAsFixed(2)}'),
                    trailing: Text(
                      invoice.isPaid ? 'Paid' : 'Due',
                      style: TextStyle(
                        color: invoice.isPaid ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
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
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Invoices Due'),
              onPressed: () {
                // TODO: Navigate to your Invoices Due page
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.work),
              label: const Text('Job Dashboard'),
              onPressed: () {
                // TODO: Navigate to your Job Dashboard page
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                final subject = Uri.encodeComponent('Test subject');
                final body = Uri.encodeComponent('Test body');
                final gmailUri = Uri(
                  scheme: 'googlegmail',
                  path: '/co',
                  queryParameters: {
                    'to': 'test@example.com',
                    'subject': subject,
                    'body': body,
                  },
                );
                if (await canLaunchUrl(gmailUri)) {
                  await launchUrl(gmailUri, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gmail app not available.')),
                  );
                }
              },
              child: const Text('Test Email'),
            ),
            ElevatedButton(
              onPressed: _testWebUrl,
              child: const Text('Test Open Google.com'),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever),
              label: const Text('Wipe Job/Invoice Data'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _confirmWipeJobData,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add Customer'),
              onPressed: _showAddCustomerDialog,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final bodyCorporateController = TextEditingController();

    final newCustomer = await showDialog<Customer>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: bodyCorporateController,
              decoration: const InputDecoration(labelText: 'Body Corporate Number (Optional)'),
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
              Navigator.pop(
                context,
                Customer(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  companyName: '',
                  address: addressController.text.trim(),
                  email: emailController.text.trim(),
                  phone: phoneController.text.trim(),
                  bodyCorporateNumber: bodyCorporateController.text.trim(),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (newCustomer != null) {
      _addCustomer(newCustomer);
    }
  }
}