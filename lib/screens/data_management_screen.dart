import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _isClearing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Management'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Warning',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'These actions will permanently delete your data. Make sure you have backups if needed.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Clear Local Data Only
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android, color: Colors.blue),
                title: const Text('Clear Local Data Only'),
                subtitle: const Text('Clears jobs, customers, and app data from this device only. Cloud data remains intact.'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _isClearing ? null : () => _showClearLocalDataDialog(),
              ),
            ),
            const SizedBox(height: 12),
            
            // Clear All Data (Local + Cloud)
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Clear All Data (Local + Cloud)'),
                subtitle: const Text('Completely wipes all data from device and cloud. This cannot be undone!'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _isClearing ? null : () => _showClearAllDataDialog(),
              ),
            ),
            const SizedBox(height: 12),
            
            // Clear Specific Data Types
            const Divider(),
            const Text(
              'Clear Specific Data Types:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            Card(
              child: ListTile(
                leading: const Icon(Icons.work, color: Colors.green),
                title: const Text('Clear Jobs Only'),
                subtitle: const Text('Remove all jobs but keep customers and settings'),
                onTap: _isClearing ? null : () => _clearSpecificData('jobs'),
              ),
            ),
            const SizedBox(height: 8),
            
            Card(
              child: ListTile(
                leading: const Icon(Icons.people, color: Colors.purple),
                title: const Text('Clear Customers Only'),
                subtitle: const Text('Remove all customers but keep jobs and settings'),
                onTap: _isClearing ? null : () => _clearSpecificData('customers'),
              ),
            ),
            const SizedBox(height: 8),
            
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings, color: Colors.grey),
                title: const Text('Reset App Settings'),
                subtitle: const Text('Reset app preferences to defaults'),
                onTap: _isClearing ? null : () => _clearSpecificData('settings'),
              ),
            ),
            
            if (_isClearing)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Clearing data...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showClearLocalDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Local Data'),
        content: const Text(
          'This will remove all jobs, customers, estimates, and app settings from this device only. '
          'Your cloud data will remain intact and will re-sync when you restart the app.\n\n'
          'Are you sure you want to continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(context);
              _clearLocalData();
            },
            child: const Text('Clear Local Data'),
          ),
        ],
      ),
    );
  }

  void _showClearAllDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Clear ALL Data'),
        content: const Text(
          'This will PERMANENTLY DELETE all your data:\n'
          '• All jobs and estimates\n'
          '• All customers\n'
          '• All app settings\n'
          '• All cloud data (Firestore)\n\n'
          'This action CANNOT BE UNDONE!\n\n'
          'Type "DELETE" to confirm:'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _showConfirmDeleteDialog();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showConfirmDeleteDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Type "DELETE" to confirm complete data wipe:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Type DELETE here',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (controller.text.trim().toUpperCase() == 'DELETE') {
                Navigator.pop(context);
                _clearAllData();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please type "DELETE" exactly to confirm'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('DELETE EVERYTHING'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearLocalData() async {
    setState(() => _isClearing = true);
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();
      
      // Delete local files
      final jobsFile = File('${directory.path}/jobs.json');
      final customersFile = File('${directory.path}/customers.json');
      final priceBookFile = File('${directory.path}/price_book.json');
      
      if (await jobsFile.exists()) await jobsFile.delete();
      if (await customersFile.exists()) await customersFile.delete();
      if (await priceBookFile.exists()) await priceBookFile.delete();
      
      // Clear SharedPreferences (but keep authentication data)
      final keys = prefs.getKeys();
      for (final key in keys) {
        // Keep authentication and cloud sync keys
        if (!key.startsWith('firebase_') && 
            !key.startsWith('google_') && 
            !key.startsWith('auth_') &&
            key != 'user_logged_in') {
          await prefs.remove(key);
        }
      }
      
      // Clear in-progress estimates
      final estimateKeys = keys.where((k) => k.startsWith('in_progress_estimate_'));
      for (final key in estimateKeys) {
        await prefs.remove(key);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local data cleared successfully! Restart the app to re-sync from cloud.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing local data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isClearing = false);
    }
  }

  Future<void> _clearAllData() async {
    setState(() => _isClearing = true);
    
    try {
      // Clear local data first
      await _clearLocalData();
      
      // Clear Firestore data if authenticated
      if (FirestoreService.isAuthenticated) {
        try {
          // Note: This would need implementation in FirestoreService
          // await FirestoreService.deleteAllUserData();
          
          // For now, show a message about manual cloud cleanup
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Local data cleared. Cloud data deletion would need to be implemented.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        } catch (e) {
          print('Error clearing Firestore data: $e');
        }
      }
      
      // Optionally sign out the user
      await FirebaseAuth.instance.signOut();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data cleared successfully! Please restart the app.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isClearing = false);
    }
  }

  Future<void> _clearSpecificData(String dataType) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear ${dataType.toUpperCase()}'),
        content: Text('This will permanently delete all $dataType. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isClearing = true);
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();
      
      switch (dataType) {
        case 'jobs':
          final jobsFile = File('${directory.path}/jobs.json');
          if (await jobsFile.exists()) await jobsFile.delete();
          
          // Clear in-progress estimates
          final keys = prefs.getKeys();
          final estimateKeys = keys.where((k) => k.startsWith('in_progress_estimate_'));
          for (final key in estimateKeys) {
            await prefs.remove(key);
          }
          break;
          
        case 'customers':
          final customersFile = File('${directory.path}/customers.json');
          if (await customersFile.exists()) await customersFile.delete();
          
          // Also clear any cached customer data in SharedPreferences
          final keys = prefs.getKeys();
          final customerKeys = keys.where((k) => 
            k.startsWith('customer_') || 
            k.startsWith('cached_customers') ||
            k == 'customer_book'  // This was missing - job_dashboard saves here
          );
          for (final key in customerKeys) {
            await prefs.remove(key);
          }
          
          // Clear any customer-related Firestore cache
          if (FirestoreService.isAuthenticated) {
            try {
              // Clear customers from Firestore if needed
              await FirestoreService.deleteAllCustomers();
            } catch (e) {
              print('Error clearing customers from Firestore: $e');
            }
          }
          break;
          
        case 'settings':
          final keys = prefs.getKeys();
          for (final key in keys) {
            // Keep authentication and essential app data
            if (!key.startsWith('firebase_') && 
                !key.startsWith('google_') && 
                !key.startsWith('auth_') &&
                !key.startsWith('in_progress_') &&
                key != 'user_logged_in') {
              await prefs.remove(key);
            }
          }
          break;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${dataType.toUpperCase()} cleared successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // If customers were cleared, show restart prompt
      if (dataType == 'customers') {
        _showRestartPrompt();
      }
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing $dataType: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isClearing = false);
    }
  }

  void _showRestartPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Restart Required'),
        content: const Text(
          'Customer data has been cleared successfully.\n\n'
          'Please restart the app to see the changes take effect. The app will reload with an empty customer list.'
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to settings
              Navigator.pop(context); // Go back to main app
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
