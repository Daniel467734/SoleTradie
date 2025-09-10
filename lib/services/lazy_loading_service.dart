import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';
import '../models/job.dart';
import '../models/customer.dart';
import '../screens/pricebook_screen.dart' as pb;

/// Service to handle lazy loading of data to prevent memory issues
class LazyLoadingService {
  static const int _jobsPerPage = 20;
  static const int _customersPerPage = 50;
  static const int _priceBookPerPage = 100;

  // Pagination cursors
  static DocumentSnapshot? _lastJobDocument;
  static DocumentSnapshot? _lastCustomerDocument;
  static DocumentSnapshot? _lastPriceBookDocument;

  // Loading states
  static bool _loadingJobs = false;
  static bool _loadingCustomers = false;
  static bool _loadingPriceBook = false;

  /// Load more jobs (pagination)
  static Future<List<Job>> loadMoreJobs() async {
    if (_loadingJobs || !FirestoreService.isAuthenticated) {
      return [];
    }

    try {
      _loadingJobs = true;
      print('Loading more jobs...');

      final jobs = await FirestoreService.getJobs(
        limit: _jobsPerPage,
        startAfter: _lastJobDocument,
      );

      if (jobs.isNotEmpty) {
        // Note: We'd need to get the last document separately for pagination
        // For now, we'll disable pagination cursor update
        // _lastJobDocument = lastJobData;
      }

      return jobs;
    } catch (e) {
      print('Error loading more jobs: $e');
      return [];
    } finally {
      _loadingJobs = false;
    }
  }

  /// Load more customers (pagination)
  static Future<List<Customer>> loadMoreCustomers() async {
    if (_loadingCustomers || !FirestoreService.isAuthenticated) {
      return [];
    }

    try {
      _loadingCustomers = true;
      print('Loading more customers...');

      final customers = await FirestoreService.getCustomers(
        limit: _customersPerPage,
        startAfter: _lastCustomerDocument,
      );

      if (customers.isNotEmpty) {
        // Note: We'd need to get the last document separately for pagination
        // For now, we'll disable pagination cursor update
        // _lastCustomerDocument = lastCustomerData;
        
        print('Loaded ${customers.length} additional customers');
      }

      return customers;
    } catch (e) {
      print('Error loading more customers: $e');
      return [];
    } finally {
      _loadingCustomers = false;
    }
  }

  /// Load more price book items (pagination)
  static Future<List<pb.PriceBookItem>> loadMorePriceBookItems() async {
    if (_loadingPriceBook || !FirestoreService.isAuthenticated) {
      return [];
    }

    try {
      _loadingPriceBook = true;
      print('Loading more price book items...');

      final items = await FirestoreService.getPriceBookItems(
        limit: _priceBookPerPage,
        startAfter: _lastPriceBookDocument,
      );

      if (items.isNotEmpty) {
        // Note: We'd need to get the last document separately for pagination
        // For now, we'll disable pagination cursor update
        // _lastPriceBookDocument = lastItemData;
        
        final priceBookItems = items.map((item) => pb.PriceBookItem.fromJson(item.toJson())).toList();
        print('Loaded ${priceBookItems.length} additional price book items');
        return priceBookItems;
      }

      return [];
    } catch (e) {
      print('Error loading more price book items: $e');
      return [];
    } finally {
      _loadingPriceBook = false;
    }
  }

  /// Reset pagination cursors (call when refreshing data)
  static void resetPagination() {
    _lastJobDocument = null;
    _lastCustomerDocument = null;
    _lastPriceBookDocument = null;
    print('Pagination cursors reset');
  }

  /// Check if currently loading jobs
  static bool get isLoadingJobs => _loadingJobs;

  /// Check if currently loading customers
  static bool get isLoadingCustomers => _loadingCustomers;

  /// Check if currently loading price book
  static bool get isLoadingPriceBook => _loadingPriceBook;

  /// Pre-load next batch of data in background (non-blocking)
  static void preloadNextBatch() {
    if (!FirestoreService.isAuthenticated) return;

    // Run in background without awaiting
    Future.microtask(() async {
      try {
        // Pre-load jobs if not currently loading
        if (!_loadingJobs && _lastJobDocument != null) {
          await loadMoreJobs();
        }
        
        // Pre-load customers if not currently loading
        if (!_loadingCustomers && _lastCustomerDocument != null) {
          await loadMoreCustomers();
        }
      } catch (e) {
        print('Background preload error: $e');
      }
    });
  }

  /// Get loading summary for debugging
  static Map<String, dynamic> getLoadingSummary() {
    return {
      'loadingJobs': _loadingJobs,
      'loadingCustomers': _loadingCustomers,
      'loadingPriceBook': _loadingPriceBook,
      'hasJobsCursor': _lastJobDocument != null,
      'hasCustomersCursor': _lastCustomerDocument != null,
      'hasPriceBookCursor': _lastPriceBookDocument != null,
    };
  }
}
