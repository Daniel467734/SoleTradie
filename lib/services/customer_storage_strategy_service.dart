import 'storage_strategy_service.dart';
import '../models/customer.dart';

/// Service to manage storage strategies for remote customers
class CustomerStorageStrategyService {
  
  /// Apply hybrid storage strategies for a remote customer
  /// This ensures all their data (jobs, documents, builds) uses hybrid storage
  static Future<void> applyRemoteCustomerStrategies(Customer customer) async {
    if (!customer.isRemote) return;
    
    print('🌐 Applying remote customer strategies for: ${customer.displayName}');
    
    // For remote customers, we want hybrid strategies for all their data
    // This ensures data is available offline but also synced to cloud
    
    // Jobs for this customer should use hybrid storage
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    
    // Documents for this customer should use hybrid storage  
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.hybridSmart);
    
    // Builds for this customer should use hybrid storage
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.hybridRecent);
    
    // In-progress builds can stay local for performance during active work
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal);
    
    print('✅ Remote customer storage strategies applied');
  }
  
  /// Remove remote customer storage strategies (revert to default)
  static Future<void> removeRemoteCustomerStrategies(Customer customer) async {
    if (customer.isRemote) return; // Still remote, don't change
    
    print('📱 Reverting to default strategies for: ${customer.displayName}');
    
    // Revert to more conservative local strategies
    // Note: This affects all customers, not just this one
    // In a full implementation, you'd want customer-specific storage rules
    
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.cloudFirst);
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal);
    
    print('✅ Default storage strategies restored');
  }
  
  /// Check if any customers are marked as remote and apply strategies accordingly
  static Future<void> syncAllRemoteCustomerStrategies(List<Customer> customers) async {
    final remoteCustomers = customers.where((c) => c.isRemote).toList();
    
    if (remoteCustomers.isEmpty) {
      print('📱 No remote customers found, using default storage strategies');
      return;
    }
    
    print('🌐 Found ${remoteCustomers.length} remote customers, applying hybrid strategies');
    
    // Apply hybrid strategies if any customers are remote
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.hybridSmart);
    await StorageStrategyService.setStrategy(DataType.builds, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.inProgressBuilds, StorageStrategy.allLocal);
    
    for (final customer in remoteCustomers) {
      print('  - ${customer.displayName} (remote)');
    }
    
    print('✅ All remote customer strategies synchronized');
  }
  
  /// Get recommended storage limits for remote customers
  static Future<DataSizeLimits> getRemoteCustomerLimits() async {
    return DataSizeLimits(
      maxLocalCustomers: 1000,      // Keep more customers locally
      maxLocalJobs: 500,           // Keep more jobs locally  
      maxLocalPriceBookItems: 2000, // Keep larger price book
      maxLocalDocuments: 200,       // Keep more documents
      maxLocalBuilds: 300,         // Keep more builds
      maxLocalInProgressBuilds: 100, // Keep more active builds
    );
  }
  
  /// Update storage limits based on remote customers
  static Future<void> updateLimitsForRemoteCustomers(List<Customer> customers) async {
    final remoteCount = customers.where((c) => c.isRemote).length;
    
    if (remoteCount == 0) return;
    
    // Increase limits based on number of remote customers
    final currentLimits = await StorageStrategyService.getDataSizeLimits();
    final remoteLimits = await getRemoteCustomerLimits();
    
    // Use the higher limits to accommodate remote customers
    final updatedLimits = DataSizeLimits(
      maxLocalCustomers: (currentLimits.maxLocalCustomers + (remoteCount * 50)).clamp(currentLimits.maxLocalCustomers, remoteLimits.maxLocalCustomers),
      maxLocalJobs: (currentLimits.maxLocalJobs + (remoteCount * 25)).clamp(currentLimits.maxLocalJobs, remoteLimits.maxLocalJobs),
      maxLocalPriceBookItems: currentLimits.maxLocalPriceBookItems.clamp(currentLimits.maxLocalPriceBookItems, remoteLimits.maxLocalPriceBookItems),
      maxLocalDocuments: (currentLimits.maxLocalDocuments + (remoteCount * 10)).clamp(currentLimits.maxLocalDocuments, remoteLimits.maxLocalDocuments),
      maxLocalBuilds: (currentLimits.maxLocalBuilds + (remoteCount * 15)).clamp(currentLimits.maxLocalBuilds, remoteLimits.maxLocalBuilds),
      maxLocalInProgressBuilds: currentLimits.maxLocalInProgressBuilds.clamp(currentLimits.maxLocalInProgressBuilds, remoteLimits.maxLocalInProgressBuilds),
    );
    
    await StorageStrategyService.updateDataSizeLimits(updatedLimits);
    
    print('📊 Updated storage limits for $remoteCount remote customers');
  }
}
