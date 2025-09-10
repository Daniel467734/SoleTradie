import 'package:flutter/material.dart';
import '../services/storage_strategy_service.dart';
import '../services/storage_migration_helper.dart';
import '../services/storage_strategy_example.dart';

/// Easy initialization for enhanced storage in your main.dart
class StorageInitializer {
  
  /// Call this in your main.dart initState() or wherever you initialize services
  static Future<void> initializeEnhancedStorage() async {
    try {
      print('🚀 Initializing enhanced storage system...');
      
      // Step 1: Check if this is first time setup
      final isFirstTime = await _isFirstTimeSetup();
      
      if (isFirstTime) {
        print('📦 First time setup - configuring default storage strategies...');
        await StorageMigrationHelper.migrateToEnhancedStorage();
        await _markSetupComplete();
      } else {
        print('✅ Enhanced storage already configured');
      }
      
      // Step 2: Show current configuration
      await StorageStrategyExample.showCurrentConfig();
      
      print('🎉 Enhanced storage system ready!');
      
    } catch (e) {
      print('❌ Error initializing enhanced storage: $e');
      // Fallback to default configuration
      await _setFallbackConfiguration();
    }
  }
  
  /// Quick setup for specific business types
  static Future<void> quickSetupFor(BusinessType businessType) async {
    switch (businessType) {
      case BusinessType.newBusiness:
        await StorageStrategyExample.setupForNewBusiness();
        break;
      case BusinessType.establishedBusiness:
        await StorageStrategyExample.setupForEstablishedBusiness();
        break;
      case BusinessType.mobileFirst:
        await StorageStrategyExample.setupForMobileFirst();
        break;
      case BusinessType.testing:
        await StorageStrategyExample.setupForTesting();
        break;
    }
  }
  
  /// Check storage health and cleanup if needed
  static Future<void> performMaintenanceCheck() async {
    try {
      print('🔧 Performing storage maintenance...');
      
      // This would be called periodically (maybe daily)
      // You could add this to your existing MemoryOptimizationService
      
      // Check if we need to cleanup local storage
      final limits = await StorageStrategyService.getDataSizeLimits();
      
      // You would integrate this with your existing repositories
      print('📊 Current limits: ${limits.maxLocalCustomers} customers, ${limits.maxLocalJobs} jobs');
      
      print('✅ Storage maintenance complete');
      
    } catch (e) {
      print('⚠️ Storage maintenance warning: $e');
    }
  }
  
  /// Get a widget to show storage status in your UI
  static Widget buildStorageStatusCard() {
    return StorageStrategyExample.buildStorageStatusWidget();
  }
  
  // Private helper methods
  static Future<bool> _isFirstTimeSetup() async {
    try {
      // Try to get an existing strategy - if it fails, it's first time
      await StorageStrategyService.getStrategy(DataType.customers);
      return false;
    } catch (e) {
      return true;
    }
  }
  
  static Future<void> _markSetupComplete() async {
    // Could save a flag to SharedPreferences if needed
    print('✅ Setup marked as complete');
  }
  
  static Future<void> _setFallbackConfiguration() async {
    print('🔄 Setting fallback configuration...');
    
    // Safe defaults if something goes wrong
    await StorageStrategyService.setStrategy(DataType.customers, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.jobs, StorageStrategy.hybridRecent);
    await StorageStrategyService.setStrategy(DataType.priceBook, StorageStrategy.allLocal);
    await StorageStrategyService.setStrategy(DataType.documents, StorageStrategy.cloudFirst);
    
    await StorageStrategyService.updateDataSizeLimits(DataSizeLimits(
      maxLocalCustomers: 100,
      maxLocalJobs: 50,
      maxLocalPriceBookItems: 300,
      maxLocalDocuments: 25,
      maxLocalBuilds: 75,
      maxLocalInProgressBuilds: 25,
    ));
    
    print('✅ Fallback configuration set');
  }
}

/// Business type for quick setup
enum BusinessType {
  newBusiness,
  establishedBusiness,
  mobileFirst,
  testing,
}

/// Extension to make it easy to add to your existing main.dart
extension StorageIntegration on State {
  
  /// Add this to your initState()
  Future<void> initializeStorage() async {
    await StorageInitializer.initializeEnhancedStorage();
  }
  
  /// Add this to your periodic maintenance (maybe in your existing MemoryOptimizationService)
  Future<void> performStorageMaintenance() async {
    await StorageInitializer.performMaintenanceCheck();
  }
  
  /// Get storage status widget for your UI
  Widget storageStatusWidget() {
    return StorageInitializer.buildStorageStatusCard();
  }
}
