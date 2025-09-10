import 'package:flutter/material.dart';
import '../services/storage_strategy_service.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  StorageStrategy _customersStrategy = StorageStrategy.hybridRecent;
  StorageStrategy _jobsStrategy = StorageStrategy.hybridRecent;
  StorageStrategy _priceBookStrategy = StorageStrategy.hybridSmart;  // Changed to hybrid
  StorageStrategy _documentsStrategy = StorageStrategy.cloudFirst;
  StorageStrategy _buildsStrategy = StorageStrategy.hybridRecent;    // New
  StorageStrategy _inProgressBuildsStrategy = StorageStrategy.allLocal; // New

  DataSizeLimits _sizeLimits = DataSizeLimits(
    maxLocalCustomers: 200,
    maxLocalJobs: 100,
    maxLocalPriceBookItems: 500,
    maxLocalDocuments: 50,
    maxLocalBuilds: 100,         // New
    maxLocalInProgressBuilds: 50, // New
  );

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final customersStrategy = await StorageStrategyService.getStrategy(DataType.customers);
      final jobsStrategy = await StorageStrategyService.getStrategy(DataType.jobs);
      final priceBookStrategy = await StorageStrategyService.getStrategy(DataType.priceBook);
      final documentsStrategy = await StorageStrategyService.getStrategy(DataType.documents);
      final buildsStrategy = await StorageStrategyService.getStrategy(DataType.builds);
      final inProgressBuildsStrategy = await StorageStrategyService.getStrategy(DataType.inProgressBuilds);
      final sizeLimits = await StorageStrategyService.getDataSizeLimits();

      setState(() {
        _customersStrategy = customersStrategy;
        _jobsStrategy = jobsStrategy;
        _priceBookStrategy = priceBookStrategy;
        _documentsStrategy = documentsStrategy;
        _buildsStrategy = buildsStrategy;
        _inProgressBuildsStrategy = inProgressBuildsStrategy;
        _sizeLimits = sizeLimits;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      print('Error loading storage settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      setState(() {
        _loading = true;
      });

      await StorageStrategyService.setStrategy(DataType.customers, _customersStrategy);
      await StorageStrategyService.setStrategy(DataType.jobs, _jobsStrategy);
      await StorageStrategyService.setStrategy(DataType.priceBook, _priceBookStrategy);
      await StorageStrategyService.setStrategy(DataType.documents, _documentsStrategy);
      await StorageStrategyService.setStrategy(DataType.builds, _buildsStrategy);
      await StorageStrategyService.setStrategy(DataType.inProgressBuilds, _inProgressBuildsStrategy);
      await StorageStrategyService.updateDataSizeLimits(_sizeLimits);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage settings saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Storage Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Data Storage Strategy',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure how your data is stored between your device and the cloud.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Customers Storage
            _buildStrategySection(
              'Customers',
              _customersStrategy,
              (strategy) => setState(() => _customersStrategy = strategy),
              'Customer contact information and details',
            ),

            const SizedBox(height: 24),

            // Jobs Storage
            _buildStrategySection(
              'Jobs',
              _jobsStrategy,
              (strategy) => setState(() => _jobsStrategy = strategy),
              'Job records, estimates, and invoices',
            ),

            const SizedBox(height: 24),

            // Price Book Storage
            _buildStrategySection(
              'Price Book',
              _priceBookStrategy,
              (strategy) => setState(() => _priceBookStrategy = strategy),
              'Price book items and catalog',
            ),

            const SizedBox(height: 24),

            // Documents Storage
            _buildStrategySection(
              'Documents',
              _documentsStrategy,
              (strategy) => setState(() => _documentsStrategy = strategy),
              'Certificates, photos, and attachments',
            ),

            const SizedBox(height: 24),

            // Builds Storage
            _buildStrategySection(
              'Estimate/Quote Builds',
              _buildsStrategy,
              (strategy) => setState(() => _buildsStrategy = strategy),
              'Completed estimate and quote builds',
            ),

            const SizedBox(height: 24),

            // In-Progress Builds Storage
            _buildStrategySection(
              'In-Progress Builds',
              _inProgressBuildsStrategy,
              (strategy) => setState(() => _inProgressBuildsStrategy = strategy),
              'Active builds being worked on',
            ),

            const SizedBox(height: 32),

            // Data Limits Section
            const Text(
              'Local Storage Limits',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Maximum number of items to keep on your device.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            _buildLimitSlider(
              'Customers',
              _sizeLimits.maxLocalCustomers,
              50,
              1000,
              (value) => setState(() => _sizeLimits = DataSizeLimits(
                maxLocalCustomers: value,
                maxLocalJobs: _sizeLimits.maxLocalJobs,
                maxLocalPriceBookItems: _sizeLimits.maxLocalPriceBookItems,
                maxLocalDocuments: _sizeLimits.maxLocalDocuments,
                maxLocalBuilds: _sizeLimits.maxLocalBuilds,
                maxLocalInProgressBuilds: _sizeLimits.maxLocalInProgressBuilds,
              )),
            ),

            _buildLimitSlider(
              'Jobs',
              _sizeLimits.maxLocalJobs,
              20,
              500,
              (value) => setState(() => _sizeLimits = DataSizeLimits(
                maxLocalCustomers: _sizeLimits.maxLocalCustomers,
                maxLocalJobs: value,
                maxLocalPriceBookItems: _sizeLimits.maxLocalPriceBookItems,
                maxLocalDocuments: _sizeLimits.maxLocalDocuments,
                maxLocalBuilds: _sizeLimits.maxLocalBuilds,
                maxLocalInProgressBuilds: _sizeLimits.maxLocalInProgressBuilds,
              )),
            ),

            _buildLimitSlider(
              'Price Book Items',
              _sizeLimits.maxLocalPriceBookItems,
              100,
              2000,
              (value) => setState(() => _sizeLimits = DataSizeLimits(
                maxLocalCustomers: _sizeLimits.maxLocalCustomers,
                maxLocalJobs: _sizeLimits.maxLocalJobs,
                maxLocalPriceBookItems: value,
                maxLocalDocuments: _sizeLimits.maxLocalDocuments,
                maxLocalBuilds: _sizeLimits.maxLocalBuilds,
                maxLocalInProgressBuilds: _sizeLimits.maxLocalInProgressBuilds,
              )),
            ),

            _buildLimitSlider(
              'Documents',
              _sizeLimits.maxLocalDocuments,
              10,
              200,
              (value) => setState(() => _sizeLimits = DataSizeLimits(
                maxLocalCustomers: _sizeLimits.maxLocalCustomers,
                maxLocalJobs: _sizeLimits.maxLocalJobs,
                maxLocalPriceBookItems: _sizeLimits.maxLocalPriceBookItems,
                maxLocalDocuments: value,
                maxLocalBuilds: _sizeLimits.maxLocalBuilds,
                maxLocalInProgressBuilds: _sizeLimits.maxLocalInProgressBuilds,
              )),
            ),

            _buildLimitSlider(
              'Builds',
              _sizeLimits.maxLocalBuilds,
              25,
              500,
              (value) => setState(() => _sizeLimits = DataSizeLimits(
                maxLocalCustomers: _sizeLimits.maxLocalCustomers,
                maxLocalJobs: _sizeLimits.maxLocalJobs,
                maxLocalPriceBookItems: _sizeLimits.maxLocalPriceBookItems,
                maxLocalDocuments: _sizeLimits.maxLocalDocuments,
                maxLocalBuilds: value,
                maxLocalInProgressBuilds: _sizeLimits.maxLocalInProgressBuilds,
              )),
            ),

            _buildLimitSlider(
              'In-Progress Builds',
              _sizeLimits.maxLocalInProgressBuilds,
              10,
              200,
              (value) => setState(() => _sizeLimits = DataSizeLimits(
                maxLocalCustomers: _sizeLimits.maxLocalCustomers,
                maxLocalJobs: _sizeLimits.maxLocalJobs,
                maxLocalPriceBookItems: _sizeLimits.maxLocalPriceBookItems,
                maxLocalDocuments: _sizeLimits.maxLocalDocuments,
                maxLocalBuilds: _sizeLimits.maxLocalBuilds,
                maxLocalInProgressBuilds: value,
              )),
            ),

            const SizedBox(height: 32),

            // Info section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Storage Strategy Guide:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('• All Local: Everything cached on device (best offline access)'),
                  Text('• Hybrid Recent: Recent items local, old items cloud-only'),
                  Text('• Hybrid Smart: Frequently used items local'),
                  Text('• Cloud First: Minimal local cache (saves device storage)'),
                  Text('• Custom: Define your own rules'),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategySection(
    String title,
    StorageStrategy currentStrategy,
    Function(StorageStrategy) onChanged,
    String description,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: StorageStrategy.values.map((strategy) {
            return ChoiceChip(
              label: Text(_getStrategyDisplayName(strategy)),
              selected: currentStrategy == strategy,
              onSelected: (selected) {
                if (selected) onChanged(strategy);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLimitSlider(
    String title,
    int currentValue,
    int min,
    int max,
    Function(int) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title: $currentValue items',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Slider(
          value: currentValue.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) / 10).round(),
          onChanged: (value) => onChanged(value.round()),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _getStrategyDisplayName(StorageStrategy strategy) {
    switch (strategy) {
      case StorageStrategy.allLocal:
        return 'All Local';
      case StorageStrategy.hybridRecent:
        return 'Hybrid Recent';
      case StorageStrategy.hybridSmart:
        return 'Hybrid Smart';
      case StorageStrategy.cloudFirst:
        return 'Cloud First';
      case StorageStrategy.custom:
        return 'Custom';
    }
  }
}
