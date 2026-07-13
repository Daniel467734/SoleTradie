import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/dashboard_screen.dart';
import 'route_observer.dart';
import 'screens/jobs_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/offline_data_screen.dart';
import 'screens/login_screen.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'services/email_service.dart';
import 'services/demo_mode_service.dart';
import 'services/memory_optimization_service.dart';
import 'services/storage_initializer.dart';
import 'services/customer_storage_strategy_service.dart';
import 'services/sync_scheduler.dart';
import 'services/storage_strategy_service.dart'; // For DataType enum
import 'services/firebase_integration_service.dart';
import 'services/service_locator.dart';
import 'firebase_options.dart';
import 'screens/scheduling_screen.dart';

import 'screens/pricebook_extensive_screen.dart' as pb;
import 'screens/customer_form_screen.dart';
import 'models/customer.dart';
import 'models/job.dart';
import 'models/estimate_version.dart';

Future<List<pb.PriceBookItem>> loadPriceBook() async {
  try {
    print('📚 Loading pricebook using hybrid approach...');
    
    // On web, skip local storage entirely and go straight to Firebase
    // because getApplicationDocumentsDirectory() throws MissingPluginException
    bool isWeb = false;
    
    // Try local storage first (fastest) - on non-web platforms only
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      
      print('📁 Looking for file at: ${file.path}');
      
      if (await file.exists()) {
        try {
          final jsonString = await file.readAsString();
          final fileSize = await file.length();
          
          print('📄 File found: size=${fileSize} bytes');
          
          if (jsonString.trim().isNotEmpty) {
            final jsonData = jsonDecode(jsonString);
            
            // Handle both old format (direct list) and new format (with metadata)
            final List<dynamic> itemsList;
            if (jsonData is Map && jsonData.containsKey('items')) {
              itemsList = jsonData['items'] as List<dynamic>;
              print('📦 Found ${itemsList.length} items in metadata format');
            } else {
              itemsList = jsonData as List<dynamic>;
              print('📦 Found ${itemsList.length} items in direct format');
            }
            
            final items = itemsList.map((e) => pb.PriceBookItem.fromJson(e)).toList();
            print('✅ Successfully loaded ${items.length} items from local storage');
            
            // Show brief loading feedback
            if (items.isNotEmpty) {
              // Try background cloud sync (non-blocking)
              _backgroundCloudSync().catchError((e) {
                print('Background sync failed: $e');
              });
            }
            
            return items;
          } else {
            print('📄 File exists but is empty');
          }
        } catch (e) {
          print('❌ Error parsing local data: $e');
          // Don't delete the file, just try other sources
        }
      } else {
        print('📄 No local file found');
      }
    } catch (e) {
      // If we can't access local storage, we're probably on web
      isWeb = true;
      print('🌐 Cannot access local storage (likely web): $e');
      print('🌐 Skipping local storage, going straight to Firebase');
    }
    
    // Try Firebase if local is empty and user is authenticated
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        print('☁️ Trying to load from Firebase...');
        await FirestoreService.initialize();
        final firestoreItems = await FirestoreService.getPriceBookItems();
        
        if (firestoreItems.isNotEmpty) {
          final items = firestoreItems.map((item) => pb.PriceBookItem.fromJson(item.toJson())).toList();
          print('☁️ Loaded ${items.length} items from cloud');
          
          // Save to local for next time (non-blocking, skip on web)
          if (!isWeb) {
            _saveToLocal(items).then((_) {
              print('💾 Cloud data cached locally');
            }).catchError((e) {
              print('Local caching failed: $e');
              return null;
            });
          }
          
          return items;
        } else {
          print('☁️ No items found in cloud');
        }
      } catch (e) {
        print('❌ Cloud loading failed: $e');
      }
    } else {
      print('👤 User not authenticated - skipping cloud');
    }
    
    // Return sample items as fallback
    final samples = _createSampleItems();
    print('🔧 Created ${samples.length} sample items as fallback');
    
    // Save sample items locally (skip on web)
    if (!isWeb) {
      _saveToLocal(samples).catchError((e) {
        print('Failed to save samples: $e');
        return null;
      });
    }
    
    return samples;
    
  } catch (e) {
    print('❌ Error loading pricebook: $e');
    return _createSampleItems();
  }
}

Future<void> _backgroundCloudSync() async {
  if (FirebaseAuth.instance.currentUser == null) return;
  
  try {
    await FirestoreService.initialize();
    final cloudItems = await FirestoreService.getPriceBookItems();
    if (cloudItems.isNotEmpty) {
      final items = cloudItems.map((item) => pb.PriceBookItem.fromJson(item.toJson())).toList();
      await _saveToLocal(items);
      print('🔄 Background sync completed: ${items.length} items');
    }
  } catch (e) {
    print('Background sync error: $e');
  }
}

Future<void> _saveToLocal(List<pb.PriceBookItem> items) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/price_book.json');
    
    print('📁 Saving to: ${file.path}');
    
    // Create directory if it doesn't exist
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    final data = {
      'items': items.map((item) => item.toJson()).toList(),
      'lastSaved': DateTime.now().toIso8601String(),
      'version': 1,
      'totalItems': items.length,
    };
    
    final jsonString = jsonEncode(data);
    await file.writeAsString(jsonString);
    
    // Verify the file was written
    final fileExists = await file.exists();
    final fileSize = await file.length();
    
    print('✅ File saved: exists=$fileExists, size=${fileSize} bytes');
    
    if (!fileExists || fileSize == 0) {
      throw Exception('File was not saved correctly');
    }
    
  } catch (e) {
    print('❌ Error saving to local: $e');
    rethrow;
  }
}

List<pb.PriceBookItem> _createSampleItems() {
  return [
    pb.PriceBookItem(
      code: 'CAL',
      name: 'Labour',
      unit: 'hr',
      groupCode: 'LABOUR',
      price: 85.0,
      purchasePrice: 65.0,
      favorite: true,
    ),
    pb.PriceBookItem(
      code: 'OUTLET',
      name: 'Power Outlet',
      unit: 'each',
      groupCode: 'ELECTRICAL',
      price: 45.0,
      purchasePrice: 25.0,
    ),
    pb.PriceBookItem(
      code: 'SWITCH',
      name: 'Light Switch',
      unit: 'each',
      groupCode: 'ELECTRICAL',
      price: 35.0,
      purchasePrice: 18.0,
    ),
  ];
}

Future<void> _logUncaughtError(String source, Object error, StackTrace? stack) async {
  final timestamp = DateTime.now().toIso8601String();
  final formatted = '''[$timestamp] $source error:\n$error\n${stack ?? ''}\n''';
  print(formatted);
  await _logMemoryStatus('error');
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/uncaught_errors.log');
    await file.writeAsString(formatted, mode: FileMode.append, flush: true);
  } catch (e) {
    print('Failed to write uncaught error log: $e');
  }
}

Future<void> _logMemoryStatus([String? context]) async {
  final summary = MemoryOptimizationService.getMemorySummary();
  final timestamp = DateTime.now().toIso8601String();
  final buffer = StringBuffer()
    ..writeln('[$timestamp] Memory status${context != null ? ' ($context)' : ''}:');
  summary.forEach((key, value) => buffer.writeln('  $key: $value'));
  buffer.writeln();
  final formatted = buffer.toString();

  print(formatted);
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/memory_status.log');
    await file.writeAsString(formatted, mode: FileMode.append, flush: true);
  } catch (e) {
    print('Failed to write memory status log: $e');
  }
}

void main() {
  BindingBase.debugZoneErrorsAreFatal = true;
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      _logUncaughtError('FlutterError', details.exception, details.stack);
    };

    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      _logUncaughtError('PlatformDispatcher', error, stack);
      return true;
    };

    await _runApp();
  }, (error, stack) async {
    await _logUncaughtError('Zone', error, stack);
  });
}

Future<void> _runApp() async {
  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');
  } catch (e, st) {
    print('❌ Firebase initialization error: $e\n$st');
    // Continue without Firebase rather than crashing
  }
  
  // Initialize with minimal blocking and memory-optimized approach
  List<pb.PriceBookItem> priceBook = [];
  List<Customer> testCustomers = [];
  
  try {
    // Initialize offline services after Firebase
    await setupServiceLocator();
    print('✅ Offline services initialized successfully');
    
    // Configure Firestore with memory limits immediately after Firebase init
    // Note: This requires the user to be signed in first

    // Restore Demo Mode state (and any previously built-up demo data) so
    // the sandbox survives an app restart while still toggled on.
    await DemoModeService.instance.initialize();

    // Use non-blocking, memory-optimized initialization
    final futures = <Future>[
      // Initialize notification service (non-blocking)
      NotificationService.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          print('Notification service initialization timed out');
        },
      ).catchError((e) {
        print('Failed to initialize notification service: $e');
      }),

      // Retry any emails left over from a previous session that never
      // finished sending (e.g. app was killed/backgrounded mid-send).
      retryPendingEmails().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('Pending email retry timed out - will try again later');
        },
      ).catchError((e) {
        print('Failed to retry pending emails: $e');
      }),
      
      // Load essential price book only (non-blocking, limited data)
      loadPriceBook().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Price book loading timed out - using empty list');
          return <pb.PriceBookItem>[];
        },
      ).then((items) {
        priceBook = items;
        print('Essential price book loaded: ${items.length} items');
      }).catchError((e) {
        print('Failed to load price book: $e');
        priceBook = <pb.PriceBookItem>[];
      }),
    ];
    
    // Wait for initialization with shorter timeout to prevent UI blocking
    await Future.wait(futures).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        print('Initialization timeout - continuing with partial setup');
        return <void>[];
      },
    );
    
  } catch (e, st) {
    print('Services initialization error: $e\n$st');
    // Continue with basic functionality
  }

  await _logMemoryStatus('startup');
  runApp(MyApp(
    initialPriceBook: priceBook,
    initialCustomers: testCustomers,
  ));
}

class MyApp extends StatefulWidget {
  final List<pb.PriceBookItem> initialPriceBook;
  final List<Customer> initialCustomers;
  const MyApp({
    super.key, 
    required this.initialPriceBook,
    required this.initialCustomers,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late List<pb.PriceBookItem> priceBook;
  List<Customer> customers = [];
  List<Job> jobs = [];
  Color _appColor = const Color(0xFF2196F3); // Default blue (primary)
  Color _accentColor = const Color(0xFF4CAF50); // Default green (secondary/accent, used app-wide for highlights)

  @override
  void initState() {
    super.initState();
    priceBook = widget.initialPriceBook;
    customers = widget.initialCustomers;
    
    // Load app color from settings
    _loadAppColor();
    
    // Initialize enhanced storage system
    _initializeEnhancedStorage();
    
    // Schedule periodic memory maintenance
    _setupMemoryMaintenance();
    
    // Initialize sync scheduler for hybrid storage
    _initializeSyncScheduler();
    
    // Enable loading from disk for proper persistence (fallback only)
    _loadDataFallback();
    
    // Listen for authentication state changes to sync data and initialize Firestore
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user != null) {
        print('✅ User authenticated: ${user.email}');
        try {
          // Initialize Firebase integration when user signs in
          await FirebaseIntegrationService.initializeForUser();

          // Register this device's FCM token now that we have a signed-in
          // user, so the "New customer added" push (sent from the
          // submitCustomerForm Cloud Function) has somewhere to deliver
          // to even if NotificationService.initialize() ran earlier at
          // app startup before sign-in completed.
          unawaited(NotificationService.registerFcmTokenForCurrentUser());
          
          // Load data local-first for an instant UI. Each call returns
          // immediately with whatever is on-device, then refreshes from
          // the cloud in the background and calls onCloudUpdate to patch
          // the UI once that finishes - avoids blocking startup for
          // 30-40+ seconds on a cold Firestore connection.
          final futures = <Future>[];
          
          futures.add(FirebaseIntegrationService.loadCustomers(
            onCloudUpdate: (cloudCustomers) {
              if (mounted) {
                setState(() {
                  customers = cloudCustomers;
                });
              }
            },
          ).then((loadedCustomers) {
            if (mounted) {
              setState(() {
                customers = loadedCustomers;
              });
            }
          }));
          
          futures.add(FirebaseIntegrationService.loadJobs(
            onCloudUpdate: (cloudJobs) {
              if (mounted) {
                setState(() {
                  jobs = cloudJobs;
                });
              }
            },
          ).then((loadedJobs) {
            if (mounted) {
              setState(() {
                jobs = loadedJobs;
              });
            }
          }));
          
          futures.add(FirebaseIntegrationService.loadPriceBook(
            onCloudUpdate: (cloudPriceBook) {
              if (mounted) {
                setState(() {
                  priceBook = cloudPriceBook;
                });
              }
            },
          ).then((loadedPriceBook) {
            if (mounted) {
              setState(() {
                priceBook = loadedPriceBook;
              });
            }
          }));
          
          await Future.wait(futures);
          print('✅ Local data loaded instantly; cloud sync continuing in background');
        } catch (e) {
          print('❌ Error initializing Firebase integration: $e');
        }
      } else {
        print('❌ User signed out');
        // Cleanup Firebase integration when user signs out
        FirebaseIntegrationService.cleanup();
      }
    });
  }

  Future<void> _loadAppColor() async {
    final prefs = await SharedPreferences.getInstance();
    final appColorString = prefs.getString('app_color');
    if (appColorString != null && appColorString.length == 9) {
      setState(() {
        _appColor = Color(int.parse(appColorString.substring(1), radix: 16));
      });
    }
    final accentColorString = prefs.getString('accent_color');
    if (accentColorString != null && accentColorString.length == 9) {
      setState(() {
        _accentColor = Color(int.parse(accentColorString.substring(1), radix: 16));
      });
    }
  }

  /// Setup periodic memory maintenance
  void _setupMemoryMaintenance() {
    // Perform memory maintenance every 5 minutes
    Stream.periodic(const Duration(minutes: 5)).listen((_) {
      MemoryOptimizationService.performMaintenance();
      
      // Also perform storage maintenance
      _performStorageMaintenance();
    });
  }

  /// Initialize sync scheduler for hybrid storage
  void _initializeSyncScheduler() {
    print('🔄 Initializing sync scheduler for hybrid storage');
    SyncScheduler.initialize();
  }

  /// Trigger immediate sync for specific data - useful for manual sync buttons
  Future<void> triggerImmediateSync(String dataType) async {
    switch (dataType.toLowerCase()) {
      case 'customers':
        await SyncScheduler.syncNow(DataType.customers);
        break;
      case 'pricebook':
        await SyncScheduler.syncNow(DataType.priceBook);
        break;
      case 'builds':
        await SyncScheduler.syncNow(DataType.builds);
        break;
      case 'estimates':
        await SyncScheduler.syncNow(DataType.estimates);
        break;
      default:
        print('⚠️ Unknown data type for sync: $dataType');
    }
  }

  /// Perform storage maintenance (cleanup, optimization)
  Future<void> _performStorageMaintenance() async {
    try {
      await StorageInitializer.performMaintenanceCheck();
    } catch (e) {
      print('Storage maintenance warning: $e');
    }
  }

  /// Initialize enhanced storage system
  Future<void> _initializeEnhancedStorage() async {
    try {
      print('🚀 Initializing enhanced storage for SoleTradie...');
      
      // Quick setup for new business (good default)
      await StorageInitializer.quickSetupFor(BusinessType.newBusiness);
      
      // Sync storage strategies for any remote customers
      await _syncRemoteCustomerStrategies();
      
      print('✅ Enhanced storage initialized successfully!');
    } catch (e) {
      print('⚠️ Enhanced storage initialization failed: $e');
      // App will continue to work with existing storage methods
    }
  }
  
  /// Sync storage strategies based on remote customers
  Future<void> _syncRemoteCustomerStrategies() async {
    try {
      // Get current customers and sync remote strategies
      await CustomerStorageStrategyService.syncAllRemoteCustomerStrategies(customers);
      
      // Update storage limits based on remote customers
      await CustomerStorageStrategyService.updateLimitsForRemoteCustomers(customers);
      
      print('🌐 Remote customer storage strategies synchronized');
    } catch (e) {
      print('⚠️ Failed to sync remote customer strategies: $e');
    }
  }

  /// Fallback data loading for when user is not authenticated
  Future<void> _loadDataFallback() async {
    try {
      // Load data using Firebase integration service (will fallback to local if not authenticated)
      final futures = <Future>[];
      
      futures.add(FirebaseIntegrationService.loadCustomers().then((loadedCustomers) {
        if (mounted) {
          setState(() {
            customers = loadedCustomers;
          });
        }
      }));
      
      futures.add(FirebaseIntegrationService.loadJobs().then((loadedJobs) {
        if (mounted) {
          setState(() {
            jobs = loadedJobs;
          });
        }
      }));
      
      futures.add(FirebaseIntegrationService.loadPriceBook().then((loadedPriceBook) {
        if (mounted) {
          setState(() {
            priceBook = loadedPriceBook;
          });
        }
      }));
      
      await Future.wait(futures);
      print('✅ Fallback data loaded successfully');
    } catch (e) {
      print('❌ Error loading fallback data: $e');
      // Create sample data if all else fails
      _createSampleData();
    }
  }

  void updatePriceBook(List<pb.PriceBookItem> updatedList) {
    print('🔄 updatePriceBook called with ${updatedList.length} items');
    print('📊 Previous pricebook had ${priceBook.length} items');
    
    setState(() {
      priceBook = updatedList;
    });
    
    print('💾 State updated, now starting save process...');
    
    // ALWAYS save locally first (immediate and blocking to ensure it completes)
    _saveToLocal(updatedList).then((_) {
      print('✅ Pricebook saved locally - SUCCESS');
      
      // Verify it was actually saved by checking the state
      print('🔍 App state now has ${priceBook.length} items');
      
      // Show immediate success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💾 Saved ${updatedList.length} items locally'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      
      // Try to save to cloud in background (non-blocking)
      if (FirebaseAuth.instance.currentUser != null) {
        _saveToCloudBackground(updatedList).then((_) {
          // Cloud sync succeeded
          print('☁️ Cloud sync also succeeded');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('☁️ Also synced to cloud'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }).catchError((e) {
          print('❌ Cloud save failed (will retry later): $e');
          // Show that local succeeded but cloud failed
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Saved locally, cloud sync failed'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        });
      } else {
        // User not authenticated
        print('👤 User not signed in for cloud sync');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💾 Saved locally (not signed in)'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }).catchError((e) {
      print('❌ CRITICAL ERROR - Local save failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Save failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }
  
  // Add this method to provide manual sync capability
  Future<bool> forceSyncPriceBookToCloud() async {
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Cannot sync - please sign in first'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return false;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 Syncing to cloud...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );

      await FirebaseIntegrationService.savePriceBook(priceBook);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Successfully synced to cloud'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Sync failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return false;
    }
  }

  Future<void> _saveToCloudBackground(List<pb.PriceBookItem> items) async {
    try {
      // Use the existing FirebaseIntegrationService which handles the conversion
      await FirebaseIntegrationService.savePriceBook(items);
      print('☁️ Cloud save completed successfully');
      
      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('☁️ Synced to cloud successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Cloud save error: $e');
      rethrow; // Let the calling method handle it
    }
  }

  void _createSampleData() {
    // Create sample customer
    final sampleCustomer = Customer(
      id: 'customer_001',
      name: 'John Smith',
      email: 'john.smith@email.com',
      phone: '(555) 123-4567',
      address: '123 Main Street, Anytown, ST 12345',
    );
    
    setState(() {
      customers = [sampleCustomer];
    });
    _saveCustomersToDisk();

    // Create sample job with invoice
    final sampleJob = Job(
      id: 'job_001',
      title: 'Kitchen Electrical Upgrade',
      description: 'Install new outlets and lighting in kitchen renovation',
      customerName: sampleCustomer.name,
      address: sampleCustomer.address,
      status: JobStatus.jobComplete,
      created: DateTime.now().subtract(const Duration(days: 10)),
      estimateItems: [],
      estimateVersions: [],
      invoices: [],
      notes: ['Customer wants dimmer switches for under-cabinet lighting'],
    );

    // Create an invoice EstimateVersion
    final invoiceVersion = EstimateVersion(
      id: 'invoice_001',
      type: 'invoice',
      status: 'final',
      amount: 1250.75,
      isPaid: false,
      isArchived: false,
      dueDate: DateTime.now().add(const Duration(days: 15)),
      invoiceNumber: 'INV-2024-001',
      items: [],
      sections: [],
    );

    sampleJob.estimateVersions.add(invoiceVersion);
    sampleJob.syncInvoices(); // This will create the Invoice object

    setState(() {
      jobs = [sampleJob];
    });
    _saveJobsToDisk();
  }

  Future<void> _saveJobsToDisk() async {
    try {
      // Save to local storage
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/jobs.json');
      final jsonList = jobs.map((job) => job.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
      
      // Also sync to Firebase if authenticated
      if (FirebaseAuth.instance.currentUser != null && FirestoreService.isAuthenticated) {
        try {
          await FirestoreService.batchSaveJobs(jobs);
          print('☁️ Jobs synced to Firebase');
        } catch (e) {
          print('❌ Failed to sync jobs to Firebase: $e');
        }
      }
    } catch (e) {
      print('❌ Error saving jobs: $e');
    }
  }

  Future<void> _saveCustomersToDisk() async {
    try {
      // Save to local storage
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/customers.json');
      final jsonList = customers.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
      
      // Also sync to Firebase if authenticated
      if (FirebaseAuth.instance.currentUser != null && FirestoreService.isAuthenticated) {
        try {
          await FirestoreService.batchSaveCustomers(customers);
          print('☁️ Customers synced to Firebase');
        } catch (e) {
          print('❌ Failed to sync customers to Firebase: $e');
        }
      }
    } catch (e) {
      print('❌ Error saving customers: $e');
    }
  }

  void _addCustomer(Customer c) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    print('[$timestamp] === _addCustomer called ===');
    print('Adding customer: ${c.name} (${c.id})');
    print('🔍 CUSTOMER EMAIL IN _addCustomer: "${c.email}"');
    print('🔍 CUSTOMER DATA IN _addCustomer: ${c.toJson()}');
    print('Current customer count before: ${customers.length}');
    
    setState(() {
      customers.add(c);
    });
    
    print('Customer added. Total customers: ${customers.length}');
    print('🔍 CUSTOMER EMAIL AFTER ADDING: "${customers.last.email}"');
    
    // Save using Firebase integration service
    FirebaseIntegrationService.saveCustomer(c).catchError((e) {
      print('❌ Error saving customer: $e');
    });
    print('=== _addCustomer completed ===');
  }

  void _updateCustomer(Customer updated) {
    setState(() {
      final idx = customers.indexWhere((c) => c.id == updated.id);
      if (idx != -1) customers[idx] = updated;
    });
    
    // Save using Firebase integration service
    FirebaseIntegrationService.saveCustomer(updated).catchError((e) {
      print('❌ Error updating customer: $e');
    });
  }

  void _removeCustomer(String id) {
    setState(() {
      customers.removeWhere((c) => c.id == id);
    });
    
    // Delete the customer locally and from Firestore. Previously this
    // incorrectly called savePriceBook() instead, so deleted customers
    // (including duplicates) were never actually removed from
    // customers.json or the cloud, and would reappear after the next sync.
    FirebaseIntegrationService.deleteCustomer(id).catchError((e) {
      print('❌ Error removing customer: $e');
    });
  }

  // Static method to get pricebook from anywhere in the app
  static Future<List<pb.PriceBookItem>> getPriceBookForApp() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final jsonData = jsonDecode(jsonString);
          
          final List<dynamic> itemsList;
          if (jsonData is Map && jsonData.containsKey('items')) {
            itemsList = jsonData['items'] as List<dynamic>;
          } else {
            itemsList = jsonData as List<dynamic>;
          }
          
          final items = itemsList.map((e) => pb.PriceBookItem.fromJson(e)).toList();
          print('📚 Loaded ${items.length} items from shared local storage');
          return items;
        }
      }
      
      print('📄 No local pricebook file found');
      return [];
    } catch (e) {
      print('❌ Error loading shared pricebook: $e');
      return [];
    }
  }
  Future<void> testLocalStorage() async {
    try {
      print('🧪 Testing local storage...');
      
      // Create test items
      final testItems = [
        pb.PriceBookItem(
          code: 'TEST1',
          name: 'Test Item 1',
          unit: 'each',
          groupCode: 'TEST',
          price: 99.99,
          purchasePrice: 50.0,
        ),
        pb.PriceBookItem(
          code: 'TEST2', 
          name: 'Test Item 2',
          unit: 'each',
          groupCode: 'TEST',
          price: 199.99,
          purchasePrice: 100.0,
        ),
      ];
      
      // Save test items
      await _saveToLocal(testItems);
      print('✅ Test items saved');
      
      // Load them back
      final loadedItems = await loadPriceBook();
      print('📚 Loaded back ${loadedItems.length} items');
      
      // Verify content
      bool foundTest1 = loadedItems.any((item) => item.code == 'TEST1');
      bool foundTest2 = loadedItems.any((item) => item.code == 'TEST2');
      
      print('🔍 Found TEST1: $foundTest1, Found TEST2: $foundTest2');
      
      if (foundTest1 && foundTest2) {
        print('✅ Local storage test PASSED');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Local storage test PASSED'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        print('❌ Local storage test FAILED');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Local storage test FAILED'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
    } catch (e) {
      print('❌ Test error: $e');
    }
  }

  /// Refresh app data from cloud and storage
  Future<void> _refreshAppData() async {
    try {
      // Reload theme colours in case they were changed in Settings
      await _loadAppColor();

      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseIntegrationService.initializeForUser();
      }

      final futures = <Future>[];
      futures.add(FirebaseIntegrationService.loadCustomers().then((loadedCustomers) {
        if (mounted) {
          setState(() {
            customers = loadedCustomers;
          });
        }
      }));
      futures.add(FirebaseIntegrationService.loadJobs().then((loadedJobs) {
        if (mounted) {
          setState(() {
            jobs = loadedJobs;
          });
        }
      }));
      futures.add(FirebaseIntegrationService.loadPriceBook().then((loadedPriceBook) {
        if (mounted) {
          setState(() {
            priceBook = loadedPriceBook;
          });
        }
      }));

      await Future.wait(futures);
    } catch (e) {
      print('❌ Error refreshing app data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TradePro',
      theme: ThemeData(
        primarySwatch: MaterialColor(_appColor.value, {
          50: _appColor.withOpacity(0.1),
          100: _appColor.withOpacity(0.2),
          200: _appColor.withOpacity(0.3),
          300: _appColor.withOpacity(0.4),
          400: _appColor.withOpacity(0.5),
          500: _appColor,
          600: _appColor.withOpacity(0.7),
          700: _appColor.withOpacity(0.8),
          800: _appColor.withOpacity(0.9),
          900: _appColor.withOpacity(1.0),
        }),
        colorScheme: ColorScheme.fromSwatch(primarySwatch: MaterialColor(_appColor.value, {
          50: _appColor.withOpacity(0.1),
          100: _appColor.withOpacity(0.2),
          200: _appColor.withOpacity(0.3),
          300: _appColor.withOpacity(0.4),
          400: _appColor.withOpacity(0.5),
          500: _appColor,
          600: _appColor.withOpacity(0.7),
          700: _appColor.withOpacity(0.8),
          800: _appColor.withOpacity(0.9),
          900: _appColor.withOpacity(1.0),
        })).copyWith(
          // App-wide selectable accent/secondary colour (defaults to green).
          // Anywhere `colorScheme.secondary` is used (e.g. Dashboard highlights,
          // totals, success accents) will follow this user-selected colour.
          secondary: _accentColor,
          onSecondary: ThemeData.estimateBrightnessForColor(_accentColor) == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Initializing SoleTradie...'),
                  ],
                ),
              ),
            );
          }
          if (snapshot.data == null) {
            return LoginScreen(onLoginSuccess: () => setState(() {}));
          }
          // User is logged in, show main app
          return DashboardScreen(
            jobs: jobs,
            customers: customers,
            priceBook: priceBook,
            onRefresh: _refreshAppData, // Pass down the refresh callback
          );
        },
      ),
      routes: {
        '/dashboard': (_) => DashboardScreen(
              jobs: jobs,
              customers: customers,
              priceBook: priceBook,
              onRefresh: _refreshAppData,
            ),
        '/jobs': (_) => JobsScreen(
              customers: customers,
              jobs: jobs,
              priceBook: priceBook,
              onAdd: _addCustomer,
              onUpdate: _updateCustomer,
              onRemove: _removeCustomer,
            ),
        '/customers': (_) => CustomersScreen(
              customers: customers,
              onAdd: _addCustomer,
              onUpdate: _updateCustomer,
              onRemove: _removeCustomer,
            ),
        '/pricebook': (_) => pb.PriceBookChoiceScreen(
              initialPriceBook: priceBook,
              onPriceBookUpdated: updatePriceBook,
            ),
        '/customer-form': (_) => const CustomerFormScreen(
              contractorName: 'SoleTradie Electrical',
              contractorCompany: 'Professional Electrical Services',
            ),
        '/offline': (_) => const OfflineDataScreen(),
        '/reports': (_) => ReportsScreen(jobs: jobs),
        '/settings': (_) => const SettingsScreen(),
        '/scheduling': (_) => SchedulingScreen(jobs: jobs, customers: customers),
      },
    );
  }
}