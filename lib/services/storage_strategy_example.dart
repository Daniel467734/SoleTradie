import 'package:flutter/material.dart';
import '../services/storage_strategy_service.dart';

/// Example of how easy it is to switch storage strategies
class StorageStrategyExample {
  
  /// Quick setup for different business scenarios
  static Future<void> setupForTesting() async {
    // Everything local for development/testing
    await StorageStrategyService.setStrategy(DataType.customers, StorageStrategy.allLocal);
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.allLocal);
    await StorageStrategyService.setStrategy(DataType.priceBook, StorageStrategy.allLocal);
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.allLocal);
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.allLocal);          // New
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal); // New
    
    print('✅ Storage configured for testing - everything local');
  }
  
  /// Setup for a new business (limited data)
  static Future<void> setupForNewBusiness() async {
    // Keep recent stuff local, but ready for cloud
    await StorageStrategyService.setStrategy(DataType.customers, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.priceBook, StorageStrategy.hybridSmart);    // Changed to hybrid
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.hybridRecent);      // New
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal); // New
    
    // Conservative limits
    await StorageStrategyService.updateDataSizeLimits(DataSizeLimits(
      maxLocalCustomers: 100,
      maxLocalJobs: 50,
      maxLocalPriceBookItems: 500,
      maxLocalDocuments: 30,
      maxLocalBuilds: 100,         // New
      maxLocalInProgressBuilds: 50, // New
    ));
    
    print('✅ Storage configured for new business');
  }
  
  /// Setup for established business (lots of historical data)
  static Future<void> setupForEstablishedBusiness() async {
    // Smart hybrid approach - keep frequently used local
    await StorageStrategyService.setStrategy(DataType.customers, StorageStrategy.hybridSmart);
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.priceBook, StorageStrategy.hybridSmart);    // Changed to hybrid
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.cloudFirst);
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.hybridRecent);      // New
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal); // New
    
    // Higher limits for active data
    await StorageStrategyService.updateDataSizeLimits(DataSizeLimits(
      maxLocalCustomers: 300,
      maxLocalJobs: 100,
      maxLocalPriceBookItems: 1000,
      maxLocalDocuments: 25, // Documents mostly in cloud
      maxLocalBuilds: 200,         // New
      maxLocalInProgressBuilds: 75, // New
    ));
    
    print('✅ Storage configured for established business');
  }
  
  /// Setup for mobile-first (limited device storage)
  static Future<void> setupForMobileFirst() async {
    // Minimal local storage, cloud-first approach
    await StorageStrategyService.setStrategy(DataType.customers, StorageStrategy.cloudFirst);
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.priceBook, StorageStrategy.hybridSmart);   // Keep some local for speed
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.cloudFirst);
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.cloudFirst);       // New
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal); // New - active work stays local
    
    // Very conservative limits
    await StorageStrategyService.updateDataSizeLimits(DataSizeLimits(
      maxLocalCustomers: 50,
      maxLocalJobs: 25,
      maxLocalPriceBookItems: 200,
      maxLocalDocuments: 10,
      maxLocalBuilds: 25,          // New
      maxLocalInProgressBuilds: 25, // New
    ));
    
    print('✅ Storage configured for mobile-first');
  }
  
  /// Show current configuration
  static Future<void> showCurrentConfig() async {
    print('📊 Current Storage Configuration:');
    
    final customerStrategy = await StorageStrategyService.getStrategy(DataType.customers);
    final jobStrategy = await StorageStrategyService.getStrategy(DataType.jobs);
    final priceBookStrategy = await StorageStrategyService.getStrategy(DataType.priceBook);
    final documentStrategy = await StorageStrategyService.getStrategy(DataType.documents);
    final buildsStrategy = await StorageStrategyService.getStrategy(DataType.builds);
    final inProgressBuildsStrategy = await StorageStrategyService.getStrategy(DataType.inProgressBuilds);
    final limits = await StorageStrategyService.getDataSizeLimits();
    
    print('  👥 Customers: ${customerStrategy.name}');
    print('  🔧 Jobs: ${jobStrategy.name}');
    print('  💰 Price Book: ${priceBookStrategy.name}');
    print('  📄 Documents: ${documentStrategy.name}');
    print('  🏗️ Builds: ${buildsStrategy.name}');
    print('  ⚡ In-Progress Builds: ${inProgressBuildsStrategy.name}');
    print('');
    print('  📏 Local Limits:');
    print('    - Customers: ${limits.maxLocalCustomers}');
    print('    - Jobs: ${limits.maxLocalJobs}');
    print('    - Price Book: ${limits.maxLocalPriceBookItems}');
    print('    - Documents: ${limits.maxLocalDocuments}');
    print('    - Builds: ${limits.maxLocalBuilds}');
    print('    - In-Progress Builds: ${limits.maxLocalInProgressBuilds}');
  }
  
  /// Example of switching individual data types
  static Future<void> exampleDynamicChanges() async {
    print('🔄 Example: Making dynamic changes...');
    
    // Maybe your customer list is getting too big - move to cloud-first
    await StorageStrategyService.setStrategy(DataType.customers, StorageStrategy.cloudFirst);
    print('  ✅ Moved customers to cloud-first');
    
    // But keep recent jobs local for offline access
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    print('  ✅ Jobs set to hybrid recent');
    
    // Price book smart hybrid for frequently used items
    await StorageStrategyService.setStrategy(DataType.priceBook, StorageStrategy.hybridSmart);
    print('  ✅ Price book set to hybrid smart');
    
    // Keep active builds local, archive old ones
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.hybridRecent);
    print('  ✅ Builds set to hybrid recent');
    
    // In-progress builds always local for performance
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal);
    print('  ✅ In-progress builds kept local');
    
    print('✅ Dynamic changes complete!');
  }
  
  /// Widget to display storage status
  static Widget buildStorageStatusWidget() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getStorageStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        
        final status = snapshot.data!;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Storage Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                _buildStatusRow('Customers', status['customers']),
                _buildStatusRow('Jobs', status['jobs']),
                _buildStatusRow('Price Book', status['priceBook']),
                _buildStatusRow('Documents', status['documents']),
                
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tap Storage Settings to customize',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // Private helper methods
  static Future<Map<String, dynamic>> _getStorageStatus() async {
    return {
      'customers': (await StorageStrategyService.getStrategy(DataType.customers)).name,
      'jobs': (await StorageStrategyService.getStrategy(DataType.jobs)).name,
      'priceBook': (await StorageStrategyService.getStrategy(DataType.priceBook)).name,
      'documents': (await StorageStrategyService.getStrategy(DataType.documents)).name,
      'builds': (await StorageStrategyService.getStrategy(DataType.builds)).name,
      'inProgressBuilds': (await StorageStrategyService.getStrategy(DataType.inProgressBuilds)).name,
    };
  }
  
  static Widget _buildStatusRow(String label, String strategy) {
    Color color;
    IconData icon;
    
    switch (strategy) {
      case 'allLocal':
        color = Colors.green;
        icon = Icons.storage;
        break;
      case 'cloudFirst':
        color = Colors.blue;
        icon = Icons.cloud;
        break;
      case 'hybridRecent':
      case 'hybridSmart':
        color = Colors.orange;
        icon = Icons.sync;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            _formatStrategyName(strategy),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  static String _formatStrategyName(String strategy) {
    switch (strategy) {
      case 'allLocal':
        return 'All Local';
      case 'cloudFirst':
        return 'Cloud First';
      case 'hybridRecent':
        return 'Hybrid Recent';
      case 'hybridSmart':
        return 'Hybrid Smart';
      default:
        return strategy;
    }
  }
}
