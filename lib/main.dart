import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/dashboard_screen.dart';
import 'screens/jobs_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/offline_data_screen.dart';
import 'screens/login_screen.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'services/memory_optimization_service.dart';
import 'services/storage_initializer.dart';
import 'services/customer_storage_strategy_service.dart';
import 'services/sync_scheduler.dart';
import 'services/storage_strategy_service.dart'; // For DataType enum
import 'services/firebase_integration_service.dart';
import 'services/service_locator.dart';

import 'screens/pricebook_screen.dart' as pb;
import 'screens/customer_form_screen.dart';
import 'models/customer.dart';
import 'models/job.dart';
import 'models/estimate_version.dart';

Future<List<pb.PriceBookItem>> loadPriceBook() async {
  // Try to load from Firebase first if user is authenticated
  if (FirebaseAuth.instance.currentUser != null) {
    try {
      await FirestoreService.initialize(); // Ensure Firestore is initialized with tenant support
      final firestoreItems = await FirestoreService.getPriceBookItems(limit: 100);
      if (firestoreItems.isNotEmpty) {
        print('✅ Loaded ${firestoreItems.length} price book items from Firebase');
        return firestoreItems.map((item) => pb.PriceBookItem.fromJson(item.toJson())).toList();
      }
    } catch (e) {
      print('❌ Error loading price book from Firebase: $e');
    }
  }
  
  // Fall back to local storage or create sample data
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/price_book.json');
    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final items = jsonList.map((e) => pb.PriceBookItem.fromJson(e)).toList();
      print('📱 Loaded ${items.length} price book items from local storage');
      return items;
    }
  } catch (e) {
    print('❌ Error loading price book from local storage: $e');
  }
  
  // Create sample price book items if none found
  final sampleItems = [
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
  
  print('🔧 Created sample price book with ${sampleItems.length} items');
  return sampleItems;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  try {
    await Firebase.initializeApp();
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
  Color _appColor = const Color(0xFF2196F3); // Default blue

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
          
          // Load data using enhanced Firebase integration
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
          print('✅ All data loaded successfully');
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
    setState(() {
      priceBook = updatedList;
    });
    
    // Save using Firebase integration service
    FirebaseIntegrationService.savePriceBook(updatedList).catchError((e) {
      print('❌ Error saving price book: $e');
    });
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
    
    // Save all customers to reflect removal
    FirebaseIntegrationService.savePriceBook(priceBook).catchError((e) {
      print('❌ Error removing customer: $e');
    });
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
        })),
      ),
      debugShowCheckedModeBanner: false,
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
          );
        },
      ),
      routes: {
        '/dashboard': (_) => DashboardScreen(
              jobs: jobs,
              customers: customers,
              priceBook: priceBook,
            ),
        '/jobs': (_) => JobsScreen(
              customers: customers,
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
        '/pricebook': (_) => pb.PriceBookScreen(
              priceBook: priceBook,
              onPriceBookUpdated: updatePriceBook,
            ),
        '/customer-form': (_) => const CustomerFormScreen(
              contractorName: 'SoleTradie Electrical',
              contractorCompany: 'Professional Electrical Services',
            ),
        '/offline': (_) => const OfflineDataScreen(),
        '/reports': (_) => ReportsScreen(jobs: jobs),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}