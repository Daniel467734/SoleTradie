import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Enhanced multi-tenant data service that scopes all business data to the authenticated user
/// while keeping app-level settings (like UI preferences) device-local
class TenantDataService {
  static FirebaseFirestore? _db;
  static String? _currentUserId;
  static String? _currentTenantId; // Company/business identifier within user account
  
  /// Initialize the service when user authenticates
  static Future<void> initialize() async {
    _db = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;
    
    if (user != null) {
      _currentUserId = user.uid;
      // Load or create tenant (business) context
      await _initializeTenant();
    }
  }
  
  /// Initialize tenant (business) context
  static Future<void> _initializeTenant() async {
    if (_currentUserId == null) return;
    
    // Check if user has a business profile
    final userDoc = await _db!.collection('users').doc(_currentUserId).get();
    
    if (userDoc.exists) {
      final userData = userDoc.data()!;
      _currentTenantId = userData['currentTenantId'] ?? _currentUserId;
    } else {
      // First time user - create default tenant
      _currentTenantId = _currentUserId;
      await _createDefaultTenant();
    }
  }
  
  /// Create default tenant for new user
  static Future<void> _createDefaultTenant() async {
    if (_currentUserId == null || _currentTenantId == null) return;
    
    // Create user document
    await _db!.collection('users').doc(_currentUserId).set({
      'currentTenantId': _currentTenantId,
      'tenants': [_currentTenantId],
      'createdAt': FieldValue.serverTimestamp(),
      'email': FirebaseAuth.instance.currentUser?.email,
    });
    
    // Create tenant document
    await _db!.collection('tenants').doc(_currentTenantId).set({
      'name': 'My Business',
      'ownerId': _currentUserId,
      'members': [_currentUserId],
      'createdAt': FieldValue.serverTimestamp(),
      'settings': {
        'businessType': 'electrical',
        'currency': 'NZD',
        'timezone': 'Pacific/Auckland',
      }
    });
    
    print('✅ Created default tenant for user: $_currentUserId');
  }
  
  /// Get current tenant ID
  static String? get currentTenantId => _currentTenantId;
  
  /// Get current user ID
  static String? get currentUserId => _currentUserId;
  
  /// Check if service is properly initialized
  static bool get isInitialized => _currentUserId != null && _currentTenantId != null && _db != null;
  
  /// Cleanup when user signs out
  static void cleanup() {
    _currentUserId = null;
    _currentTenantId = null;
    _db = null;
  }
  
  // TENANT-SCOPED DATA OPERATIONS
  
  /// Get tenant-scoped collection reference
  static CollectionReference<Map<String, dynamic>>? getTenantCollection(String collectionName) {
    if (!isInitialized) return null;
    return _db!.collection('tenants/$_currentTenantId/$collectionName');
  }
  
  /// Save business data (tenant-scoped)
  static Future<void> saveTenantData(String key, dynamic value) async {
    if (!isInitialized) throw Exception('TenantDataService not initialized');
    
    await _db!.collection('tenants').doc(_currentTenantId).update({
      'data.$key': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  
  /// Load business data (tenant-scoped)
  static Future<T?> loadTenantData<T>(String key) async {
    if (!isInitialized) return null;
    
    final doc = await _db!.collection('tenants').doc(_currentTenantId).get();
    if (!doc.exists) return null;
    
    final data = doc.data();
    return data?['data']?[key] as T?;
  }
  
  /// Save business settings (tenant-scoped, but kept in SharedPreferences for backward compatibility)
  static Future<void> saveBusinessSetting(String key, dynamic value) async {
    if (!isInitialized) {
      // Fallback to local storage if not authenticated
      final prefs = await SharedPreferences.getInstance();
      if (value is String) {
        await prefs.setString('business_$key', value);
      } else if (value is bool) {
        await prefs.setBool('business_$key', value);
      } else if (value is int) {
        await prefs.setInt('business_$key', value);
      } else if (value is double) {
        await prefs.setDouble('business_$key', value);
      } else {
        await prefs.setString('business_$key', json.encode(value));
      }
      return;
    }
    
    // Save both to cloud and local for offline access
    await Future.wait([
      saveTenantData(key, value),
      _saveLocalBusinessSetting(key, value),
    ]);
  }
  
  /// Load business settings (tenant-scoped)
  static Future<T?> loadBusinessSetting<T>(String key) async {
    if (!isInitialized) {
      // Fallback to local storage if not authenticated
      return await _loadLocalBusinessSetting<T>(key);
    }
    
    try {
      // Try cloud first
      final cloudValue = await loadTenantData<T>(key);
      if (cloudValue != null) {
        // Cache locally for offline access
        await _saveLocalBusinessSetting(key, cloudValue);
        return cloudValue;
      }
    } catch (e) {
      print('Failed to load from cloud, using local: $e');
    }
    
    // Fallback to local
    return await _loadLocalBusinessSetting<T>(key);
  }
  
  /// Save app-level settings (device-local, not tenant-scoped)
  static Future<void> saveAppSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString('app_$key', value);
    } else if (value is bool) {
      await prefs.setBool('app_$key', value);
    } else if (value is int) {
      await prefs.setInt('app_$key', value);
    } else if (value is double) {
      await prefs.setDouble('app_$key', value);
    } else {
      await prefs.setString('app_$key', json.encode(value));
    }
  }
  
  /// Load app-level settings (device-local)
  static Future<T?> loadAppSetting<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (T == String) {
      return prefs.getString('app_$key') as T?;
    } else if (T == bool) {
      return prefs.getBool('app_$key') as T?;
    } else if (T == int) {
      return prefs.getInt('app_$key') as T?;
    } else if (T == double) {
      return prefs.getDouble('app_$key') as T?;
    } else {
      final stringValue = prefs.getString('app_$key');
      if (stringValue != null) {
        return json.decode(stringValue) as T;
      }
    }
    return null;
  }
  
  // HELPER METHODS FOR LOCAL STORAGE
  
  static Future<void> _saveLocalBusinessSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    final tenantKey = 'tenant_${_currentTenantId}_$key';
    
    if (value is String) {
      await prefs.setString(tenantKey, value);
    } else if (value is bool) {
      await prefs.setBool(tenantKey, value);
    } else if (value is int) {
      await prefs.setInt(tenantKey, value);
    } else if (value is double) {
      await prefs.setDouble(tenantKey, value);
    } else {
      await prefs.setString(tenantKey, json.encode(value));
    }
  }
  
  static Future<T?> _loadLocalBusinessSetting<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final tenantKey = 'tenant_${_currentTenantId}_$key';
    
    if (T == String) {
      return prefs.getString(tenantKey) as T?;
    } else if (T == bool) {
      return prefs.getBool(tenantKey) as T?;
    } else if (T == int) {
      return prefs.getInt(tenantKey) as T?;
    } else if (T == double) {
      return prefs.getDouble(tenantKey) as T?;
    } else {
      final stringValue = prefs.getString(tenantKey);
      if (stringValue != null) {
        try {
          return json.decode(stringValue) as T;
        } catch (e) {
          print('Failed to decode tenant data for key $key: $e');
        }
      }
    }
    return null;
  }
  
  // MIGRATION HELPERS
  
  /// Migrate existing SharedPreferences data to tenant-scoped storage
  static Future<void> migrateExistingData() async {
    if (!isInitialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    // Business data keys that should be migrated to tenant scope
    final businessKeys = [
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
      'gps_visit_history',
      // Add more as needed
    ];
    
    for (final key in businessKeys) {
      if (keys.contains(key)) {
        final value = _getPreferenceValue(prefs, key);
        if (value != null) {
          await saveBusinessSetting(key, value);
          print('✅ Migrated $key to tenant scope');
        }
      }
    }
    
    // Mark migration as complete
    await saveAppSetting('migration_completed', true);
    print('✅ Data migration to tenant scope completed');
  }
  
  static dynamic _getPreferenceValue(SharedPreferences prefs, String key) {
    final keys = prefs.getKeys();
    if (!keys.contains(key)) return null;
    
    // Try different types
    try {
      return prefs.getString(key);
    } catch (e) {
      try {
        return prefs.getBool(key);
      } catch (e) {
        try {
          return prefs.getInt(key);
        } catch (e) {
          try {
            return prefs.getDouble(key);
          } catch (e) {
            return null;
          }
        }
      }
    }
  }
}
