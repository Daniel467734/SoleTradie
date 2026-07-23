import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_integration_service.dart';

/// Debug screen to diagnose cloud sync issues
/// Shows: Authentication status, Firestore connection, data counts, and error details
class CloudStatusDebugScreen extends StatefulWidget {
  const CloudStatusDebugScreen({Key? key}) : super(key: key);

  @override
  State<CloudStatusDebugScreen> createState() => _CloudStatusDebugScreenState();
}

class _CloudStatusDebugScreenState extends State<CloudStatusDebugScreen> {
  String _status = 'Loading...';
  String _authStatus = 'Checking...';
  String _firestoreStatus = 'Checking...';
  int _jobCount = 0;
  int _customerCount = 0;
  int _priceBookCount = 0;
  List<String> _errors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _diagnose();
  }

  Future<void> _diagnose() async {
    try {
      // 1. Check Authentication
      print('🔍 DIAGNOSTIC: Checking authentication...');
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _authStatus = '✅ Authenticated\nUID: ${user.uid}\nEmail: ${user.email}';
        print('✅ User authenticated: ${user.email}');
      } else {
        _authStatus = '❌ NOT authenticated\nPlease log in first';
        _errors.add('User not authenticated');
        setState(() => _isLoading = false);
        return;
      }

      // 2. Check Firestore Connection
      print('🔍 DIAGNOSTIC: Checking Firestore connection...');
      try {
        // Try a simple query to check connectivity
        final testQuery = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));
        
        await testQuery.timeout(const Duration(seconds: 5));
        _firestoreStatus = '✅ Connected to Firestore';
        print('✅ Firestore connected');
      } catch (e) {
        _firestoreStatus = '❌ Firestore error: $e';
        _errors.add('Firestore connection failed: $e');
        print('❌ Firestore connection error: $e');
      }

      // 3. Check Job Count
      print('🔍 DIAGNOSTIC: Checking jobs collection...');
      try {
        final jobsSnapshot = await FirebaseFirestore.instance
            .collection('users/${user.uid}/jobs')
            .get(const GetOptions(source: Source.server));
        _jobCount = jobsSnapshot.docs.length;
        print('✅ Jobs found: $_jobCount');
      } catch (e) {
        _errors.add('Failed to fetch jobs: $e');
        print('❌ Jobs fetch error: $e');
      }

      // 4. Check Customer Count
      print('🔍 DIAGNOSTIC: Checking customers collection...');
      try {
        final customersSnapshot = await FirebaseFirestore.instance
            .collection('users/${user.uid}/customers')
            .get(const GetOptions(source: Source.server));
        _customerCount = customersSnapshot.docs.length;
        print('✅ Customers found: $_customerCount');
      } catch (e) {
        _errors.add('Failed to fetch customers: $e');
        print('❌ Customers fetch error: $e');
      }

      // 5. Check Price Book Count
      print('🔍 DIAGNOSTIC: Checking price book collection...');
      try {
        final priceBookSnapshot = await FirebaseFirestore.instance
            .collection('users/${user.uid}/priceBook')
            .get(const GetOptions(source: Source.server));
        _priceBookCount = priceBookSnapshot.docs.length;
        print('✅ Price book items found: $_priceBookCount');
      } catch (e) {
        _errors.add('Failed to fetch price book: $e');
        print('❌ Price book fetch error: $e');
      }

      // 6. Try loading via FirebaseIntegrationService
      print('🔍 DIAGNOSTIC: Testing FirebaseIntegrationService...');
      try {
        print('  - Loading customers...');
        final customers = await FirebaseIntegrationService.loadCustomers()
            .timeout(const Duration(seconds: 10));
        print('  ✅ Loaded ${customers.length} customers via service');

        print('  - Loading jobs...');
        final jobs = await FirebaseIntegrationService.loadJobs()
            .timeout(const Duration(seconds: 10));
        print('  ✅ Loaded ${jobs.length} jobs via service');
      } catch (e) {
        _errors.add('FirebaseIntegrationService error: $e');
        print('❌ FirebaseIntegrationService error: $e');
      }

      _status = '✅ Diagnostic Complete';
    } catch (e) {
      _status = '❌ Diagnostic Failed: $e';
      _errors.add('$e');
      print('❌ Diagnostic error: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('☁️ Cloud Status Debug'),
        backgroundColor: Colors.deepPurple,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Running diagnostics...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overall Status
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _status.contains('Complete')
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _status.contains('Complete')
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    child: Text(
                      _status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Authentication Status
                  _buildCard(
                    title: '🔐 Authentication',
                    content: _authStatus,
                    isError: _authStatus.contains('❌'),
                  ),
                  const SizedBox(height: 12),

                  // Firestore Connection Status
                  _buildCard(
                    title: '🔗 Firestore Connection',
                    content: _firestoreStatus,
                    isError: _firestoreStatus.contains('❌'),
                  ),
                  const SizedBox(height: 12),

                  // Data Counts
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📊 Cloud Data Counts',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildCountBubble('Jobs', _jobCount),
                              _buildCountBubble('Customers', _customerCount),
                              _buildCountBubble('Price Book', _priceBookCount),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Errors
                  if (_errors.isNotEmpty) ...[
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '❌ Errors (${_errors.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            for (final error in _errors)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  '• $error',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ] else
                    Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No errors detected',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Re-check'),
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errors.clear();
                          });
                          _diagnose();
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCard({
    required String title,
    required String content,
    required bool isError,
  }) {
    return Card(
      color: isError ? Colors.red.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: TextStyle(
                fontSize: 12,
                color: isError ? Colors.red.shade700 : Colors.green.shade700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountBubble(String label, int count) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
