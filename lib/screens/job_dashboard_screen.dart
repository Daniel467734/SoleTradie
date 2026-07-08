import 'package:flutter/material.dart';
import 'settings_screen.dart';
import '../route_observer.dart';

class JobDashboardScreen extends StatefulWidget {
  final String userId;

  const JobDashboardScreen({super.key, required this.userId});

  @override
  State<JobDashboardScreen> createState() => _JobDashboardScreenState();
}

class _JobDashboardScreenState extends State<JobDashboardScreen> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async { await _showCreateJobDialog(context); setState(() {}); },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              setState(() {});
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search bar
            TextField(textCapitalization: TextCapitalization.sentences, 
              decoration: InputDecoration(
                hintText: 'Search jobs',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Filter by Status
            Row(
              children: [
                const Icon(Icons.filter_list),
                const SizedBox(width: 8),
                Expanded(
                  flex: 0,
                  child: const Text('Status:', overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: 'Active',
                    items: const [
                      DropdownMenuItem(value: 'Active', child: Text('Active')),
                      DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                      DropdownMenuItem(value: 'All', child: Text('All')),
                    ],
                    onChanged: (value) {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Jobs list or empty state
            Expanded(
              child: Center(
                child: Text('0 jobs found'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateJobDialog(BuildContext context) async {
    final customerNameController = TextEditingController();
    final addressController = TextEditingController();
    final orderNumberController = TextEditingController();
    final customers = <String>[
      'Acme Installations',
      'Bayview Electrical',
      'Cedar Construction',
      'Delta Plumbing',
      'Elm Services',
    ];
    String? selectedCustomer;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create New Job'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: customerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedCustomer != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Selected customer: $selectedCustomer',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: 160,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final isSelected = customer == selectedCustomer;
                      return ListTile(
                        title: Text(customer),
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? Colors.green : null,
                        ),
                        onTap: () {
                          setState(() {
                            selectedCustomer = customer;
                            customerNameController.text = customer;
                            customers.removeAt(index);
                            customers.insert(0, customer);
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Site Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: orderNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Order Number (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., ORD-2024-001',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // For now, just close the dialog - we'll connect this to actual job creation later
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Job creation coming soon!')),
                );
              },
              child: const Text('Create Job'),
            ),
          ],
        ),
      ),
    ).then((_) {
      customerNameController.dispose();
      addressController.dispose();
      orderNumberController.dispose();
    });
  }
}