import 'package:shared_preferences/shared_preferences.dart';
import 'tenant_data_service.dart';

/// Helper class to migrate settings from SharedPreferences to tenant-scoped storage
class SettingsMigrationHelper {
  
  /// Business settings that should be migrated to tenant scope
  static const businessSettingsKeys = [
    'company_name',
    'company_address', 
    'gst_number',
    'is_gst_registered',
    'company_logo_path',
    'full_name',
    'main_email',
    'phone_number',
    'signature_path',
    'bank_details',
    'smtp_email',
    'smtp_password',
    'smtp_server',
    'smtp_port',
    'pricing_multiplier',
    'auto_email_certificates',
    'has_accepted_terms',
    'show_line_item_prices_default',
    'country_region',
    'auto_backup_enabled',
    'gps_visit_history',
    'estimate_templates',
    'last_document_number',
  ];
  
  /// App-level settings that should remain device-local
  static const appSettingsKeys = [
    'app_color',
    'pdf_color',
    'dark_mode',
    'migration_completed',
    'first_run',
    'tutorial_completed',
    'ui_scale',
    'notifications_enabled',
  ];
  
  /// Migrate a specific business setting to tenant scope
  static Future<void> migrateBusinessSetting(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (!prefs.containsKey(key)) return;
      
      // Get the value from SharedPreferences
      dynamic value;
      if (prefs.get(key) is String) {
        value = prefs.getString(key);
      } else if (prefs.get(key) is bool) {
        value = prefs.getBool(key);
      } else if (prefs.get(key) is int) {
        value = prefs.getInt(key);
      } else if (prefs.get(key) is double) {
        value = prefs.getDouble(key);
      } else if (prefs.get(key) is List<String>) {
        value = prefs.getStringList(key);
      }
      
      if (value != null) {
        // Save to tenant-scoped storage
        await TenantDataService.saveBusinessSetting(key, value);
        
        // Remove from SharedPreferences (optional - can keep for backward compatibility)
        // await prefs.remove(key);
        
        print('✅ Migrated business setting: $key');
      }
    } catch (e) {
      print('❌ Failed to migrate business setting $key: $e');
    }
  }
  
  /// Migrate an app setting to proper app scope
  static Future<void> migrateAppSetting(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (!prefs.containsKey(key)) return;
      
      // Get the value from SharedPreferences
      dynamic value;
      if (prefs.get(key) is String) {
        value = prefs.getString(key);
      } else if (prefs.get(key) is bool) {
        value = prefs.getBool(key);
      } else if (prefs.get(key) is int) {
        value = prefs.getInt(key);
      } else if (prefs.get(key) is double) {
        value = prefs.getDouble(key);
      }
      
      if (value != null) {
        // Save to app-scoped storage
        await TenantDataService.saveAppSetting(key, value);
        print('✅ Migrated app setting: $key');
      }
    } catch (e) {
      print('❌ Failed to migrate app setting $key: $e');
    }
  }
  
  /// Migrate all settings to their appropriate scopes
  static Future<void> migrateAllSettings() async {
    print('🔄 Starting settings migration...');
    
    // Migrate business settings to tenant scope
    for (final key in businessSettingsKeys) {
      await migrateBusinessSetting(key);
    }
    
    // Migrate app settings to app scope
    for (final key in appSettingsKeys) {
      await migrateAppSetting(key);
    }
    
    // Mark migration as complete
    await TenantDataService.saveAppSetting('settings_migration_completed', true);
    
    print('✅ Settings migration completed');
  }
  
  /// Check if settings migration is needed
  static Future<bool> needsMigration() async {
    final migrationCompleted = await TenantDataService.loadAppSetting<bool>('settings_migration_completed') ?? false;
    return !migrationCompleted && TenantDataService.isInitialized;
  }
}

/// Extension to make it easy to use tenant-scoped settings throughout the app
extension TenantSettings on SharedPreferences {
  
  /// Get a business setting (tenant-scoped)
  Future<T?> getBusinessSetting<T>(String key) async {
    return await TenantDataService.loadBusinessSetting<T>(key);
  }
  
  /// Set a business setting (tenant-scoped)
  Future<void> setBusinessSetting(String key, dynamic value) async {
    await TenantDataService.saveBusinessSetting(key, value);
  }
  
  /// Get an app setting (device-local)
  Future<T?> getAppSetting<T>(String key) async {
    return await TenantDataService.loadAppSetting<T>(key);
  }
  
  /// Set an app setting (device-local)
  Future<void> setAppSetting(String key, dynamic value) async {
    await TenantDataService.saveAppSetting(key, value);
  }
}
