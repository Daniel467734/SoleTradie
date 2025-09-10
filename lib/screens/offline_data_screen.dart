import 'package:flutter/material.dart';
// Updated imports to use mock implementations
import '../services/price_book_local_data_source.dart';
import '../services/customer_local_data_source.dart';
import '../models/price_book_item.dart';
import '../models/sync_customer.dart';

class OfflineDataScreen extends StatefulWidget {
  const OfflineDataScreen({super.key});

  @override
  State<OfflineDataScreen> createState() => _OfflineDataScreenState();
}

class _OfflineDataScreenState extends State<OfflineDataScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late PriceBookLocalDataSource _priceBookDataSource;
  late CustomerLocalDataSource _customerDataSource;
  
  List<PriceBookItem> _priceBookItems = [];
  List<SyncCustomer> _customers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _priceBookDataSource = PriceBookLocalDataSource();
    _customerDataSource = CustomerLocalDataSource();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final priceBookItems = await _priceBookDataSource.getAll();
      final customers = await _customerDataSource.getAll();
      
      setState(() {
        _priceBookItems = priceBookItems;
        _customers = customers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _addSamplePriceBookItem() async {
    final item = PriceBookItem(
      code: 'CABLE-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Electrical Cable 2.5mm',
      category: 'Cables',
      salePrice: 25.00,
    );

    await _priceBookDataSource.insert(item);
    await _loadData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Price book item added!')),
      );
    }
  }

  Future<void> _addSampleCustomer() async {
    final customer = SyncCustomer(
      customerId: 'CUST-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Sample Customer ${DateTime.now().millisecond}',
      email: 'customer@example.com',
      phone: '+64 21 123 4567',
    );

    await _customerDataSource.insert(customer);
    await _loadData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer added!')),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Data Management'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inventory), text: 'Price Book'),
            Tab(icon: Icon(Icons.people), text: 'Customers'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPriceBookTab(),
                _buildCustomersTab(),
              ],
            ),
    );
  }

  Widget _buildPriceBookTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Price Book Items (${_priceBookItems.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addSamplePriceBookItem,
                icon: const Icon(Icons.add),
                label: const Text('Add Sample'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _priceBookItems.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No price book items yet'),
                      Text('Add some items to see offline sync in action'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _priceBookItems.length,
                  itemBuilder: (context, index) {
                    final item = _priceBookItems[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text(item.name),
                        subtitle: Text('${item.code} - ${item.category ?? 'No category'}'),
                        trailing: SizedBox(
                          width: 80,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('\$${item.salePrice.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.needsSync ? Icons.sync_problem : Icons.cloud_done,
                                    size: 16,
                                    color: item.needsSync ? Colors.orange : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      item.needsSync ? 'Pending' : 'Synced',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: item.needsSync ? Colors.orange : Colors.green,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCustomersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Customers (${_customers.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addSampleCustomer,
                icon: const Icon(Icons.add),
                label: const Text('Add Sample'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _customers.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No customers yet'),
                      Text('Add some customers to see offline sync in action'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _customers.length,
                  itemBuilder: (context, index) {
                    final customer = _customers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(customer.name.isNotEmpty ? customer.name[0] : 'C'),
                        ),
                        title: Text(customer.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (customer.email?.isNotEmpty == true) Text(customer.email!),
                            if (customer.phone?.isNotEmpty == true) Text(customer.phone!),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (customer.isRemote)
                              const Icon(Icons.offline_pin, color: Colors.green),
                            Icon(
                              customer.needsSync ? Icons.sync_problem : Icons.cloud_done,
                              size: 16,
                              color: customer.needsSync ? Colors.orange : Colors.green,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
