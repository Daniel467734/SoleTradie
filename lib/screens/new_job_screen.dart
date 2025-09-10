import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../screens/customer_picker_screen.dart';
import '../services/firestore_service.dart';

class NewJobScreen extends StatefulWidget {
  const NewJobScreen({super.key});

  @override
  State<NewJobScreen> createState() => _NewJobScreenState();
}

class _NewJobScreenState extends State<NewJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _jobNameController = TextEditingController();
  Customer? selectedCustomer;
  List<Customer> customers = [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final loadedCustomers = await FirestoreService.getCustomers();
      setState(() {
        customers = loadedCustomers;
      });
    } catch (e) {
      print('Error loading customers: $e');
    }
  }

  Future<void> _selectCustomer() async {
    final customer = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerPickerScreen(customers: customers),
      ),
    );
    
    if (customer != null) {
      setState(() {
        selectedCustomer = customer;
      });
      // Reload customers in case a new one was added
      _loadCustomers();
    }
  }

  void _createJob() {
    final jobName = _jobNameController.text.trim();
    if (jobName.isEmpty || selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a job name and select a customer.')),
      );
      return;
    }
    Navigator.pop(context, {
      'jobName': jobName, 
      'customer': selectedCustomer,
      'customerName': selectedCustomer!.name,
      'customerAddress': selectedCustomer!.address,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Job'),
        backgroundColor: Colors.indigo,
        elevation: 2,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Card(
            elevation: 8,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.work, size: 60, color: Colors.indigo),
                    const SizedBox(height: 18),
                    Text(
                      'New Job Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.indigo[700],
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _jobNameController,
                      decoration: const InputDecoration(
                        labelText: 'Job Name',
                        prefixIcon: Icon(Icons.edit),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 22),
                    // Customer Selection
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.person_search, color: Colors.indigo),
                        title: Text(
                          selectedCustomer?.name ?? 'Select Customer',
                          style: TextStyle(
                            color: selectedCustomer != null ? Colors.black : Colors.grey[600],
                          ),
                        ),
                        subtitle: selectedCustomer != null 
                          ? Text(
                              selectedCustomer!.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : const Text('Tap to choose or add a customer'),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: _selectCustomer,
                      ),
                    ),
                    if (selectedCustomer == null)
                      const Padding(
                        padding: EdgeInsets.only(left: 12, top: 8),
                        child: Text(
                          'Please select a customer',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          if (_formKey.currentState?.validate() ?? false) {
                            _createJob();
                          }
                        },
                        label: const Text(
                          'Create Job',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    // Extra spacing to lift buttons above phone navigation
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}