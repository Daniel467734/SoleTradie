import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/storage_strategy_service.dart';
import '../services/enhanced_customer_repository.dart';
import '../services/customer_local_data_source.dart';
import '../services/remote_data_source.dart';
import '../services/sync_service_impl.dart';

/// Helper to migrate from current repository to enhanced storage strategy
class StorageMigrationHelper {
  
  /// Easy one-step migration from your current setup
  static Future<void> migrateToEnhancedStorage() async {
    print('🚀 Starting migration to enhanced storage...');
    
    // Step 1: Set default strategies (you can change these anytime)
    await _setDefaultStrategies();
    
    // Step 2: Set reasonable limits
    await _setDefaultLimits();
    
    print('✅ Migration complete! Your app now has flexible storage strategies.');
    print('💡 Go to Settings > Storage Settings to customize further.');
  }
  
  /// Replace your current CustomerRepository with EnhancedCustomerRepository
  static Future<EnhancedCustomerRepository> createEnhancedCustomerRepository() async {
    // Use your existing data sources
    final localDataSource = CustomerLocalDataSource();
    final remoteDataSource = CustomerRemoteDataSource();
    
    // Create a SyncService instance for hybrid saving functionality
    final syncService = SyncService(Connectivity());
    
    return EnhancedCustomerRepository(
      localDataSource,
      remoteDataSource,
      syncService,
    );
  }
  
  /// Example usage in your app initialization
  static Future<void> setupInMainApp() async {
    // In your main.dart or wherever you initialize services:
    
    print('🔧 Setting up enhanced storage...');
    
    // 1. Migrate to enhanced storage (only needed once)
    await migrateToEnhancedStorage();
    
    // 2. Create your enhanced repository
    final customerRepository = await createEnhancedCustomerRepository();
    
    // 3. Use it exactly like your old repository
    final allCustomers = await customerRepository.getAll();
    print('📊 Loaded ${allCustomers.length} customers with new storage strategy');
    
    // 4. The repository now automatically handles storage strategies!
    // - Recent customers stay local
    // - Old customers move to cloud
    // - Everything syncs automatically
    // - User can change strategies anytime
    
    print('✅ Enhanced storage is ready!');
  }
  
  /// Show storage savings and benefits
  static Future<void> showStorageBenefits() async {
    print('📈 Storage Strategy Benefits:');
    print('');
    print('🏠 Local Storage:');
    print('  ✅ Instant access (no network needed)');
    print('  ✅ Works offline');
    print('  ✅ Fast search and filtering');
    print('  ❌ Uses device storage');
    print('');
    print('☁️  Cloud Storage:');
    print('  ✅ Unlimited capacity');
    print('  ✅ Accessible from anywhere');
    print('  ✅ Automatic backup');
    print('  ❌ Requires internet');
    print('');
    print('🔄 Hybrid Storage (Best of Both):');
    print('  ✅ Recent/important data locally');
    print('  ✅ Old/rarely used data in cloud');
    print('  ✅ Automatic management');
    print('  ✅ User can customize');
    print('');
    
    final limits = await StorageStrategyService.getDataSizeLimits();
    print('📏 Your Current Limits:');
    print('  • ${limits.maxLocalCustomers} customers locally');
    print('  • ${limits.maxLocalJobs} jobs locally');
    print('  • ${limits.maxLocalPriceBookItems} price book items locally');
    print('  • ${limits.maxLocalDocuments} documents locally');
  }
  
  // Private helper methods
  static Future<void> _setDefaultStrategies() async {
    // Conservative defaults that work well for most businesses
    await StorageStrategyService.setStrategy(DataType.customers, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.priceBook, StorageStrategy.allLocal);
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.cloudFirst);
    
    print('✅ Set default storage strategies');
  }
  
  static Future<void> _setDefaultLimits() async {
    await StorageStrategyService.updateDataSizeLimits(DataSizeLimits(
      maxLocalCustomers: 200,  // Recent customers
      maxLocalJobs: 100,       // Recent jobs
      maxLocalPriceBookItems: 500, // Essential price book
      maxLocalDocuments: 50,   // Recent documents
      maxLocalBuilds: 100,     // Recent builds
      maxLocalInProgressBuilds: 25, // In-progress builds
    ));
    
    print('✅ Set default storage limits');
  }
}
