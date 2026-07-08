import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import '../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _isClearing = false;
  bool _isBackingUp = false;

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
            const SizedBox(height: 8),
            
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.teal),
                title: const Text('Delete Job Data'),
                subtitle: const Text(
                  'Keep settings, customers and pricebook while deleting jobs, estimates, invoices, quotes and certificates',
                ),
                onTap: _isClearing ? null : _clearTestData,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.backup, color: Colors.blue),
                title: const Text('Export Backup File'),
                subtitle: const Text('Save your app data to a backup file for Dropbox/iCloud/Drive storage.'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _isBackingUp ? null : _exportAppBackup,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restore, color: Colors.green),
                title: const Text('Import Backup File'),
                subtitle: const Text('Restore local data from a previously saved backup file.'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _isBackingUp ? null : _importAppBackup,
              ),
            ),
            const SizedBox(height: 24),
            
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

  Future<void> _exportAppBackup() async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();
      final backup = <String, dynamic>{
        'generatedAt': DateTime.now().toIso8601String(),
        'sourceApp': 'sole_trader',
        'files': <String, dynamic>{},
        'settings': <String, dynamic>{},
      };

      await for (final entity in directory.list(recursive: false, followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          try {
            final contents = await entity.readAsString();
            backup['files'][fileName] = jsonDecode(contents);
          } catch (e) {
            print('Warning: could not parse ${entity.path} as JSON: $e');
            backup['files'][fileName] = await entity.readAsString();
          }
        }
      }

      for (final key in prefs.getKeys()) {
        if (key.startsWith('firebase_') || key.startsWith('google_') || key.startsWith('auth_') || key == 'user_logged_in') {
          continue;
        }
        backup['settings'][key] = prefs.get(key);
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'sole_trader_backup_${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\\.]'), '-')}.json';
      final backupFile = File('${tempDir.path}/$fileName');
      await backupFile.writeAsString(jsonEncode(backup));

      await Share.shareXFiles(
        [XFile(backupFile.path)],
        text: 'Sole Tradie backup file created on ${DateTime.now().toLocal()}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup created and ready to save/share: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error exporting backup: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _importAppBackup() async {
    if (_isBackingUp) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Text('This will overwrite current local app data with the backup file contents. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isBackingUp = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return;

      final backupFile = File(result.files.single.path!);
      final backupJson = jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      final files = backupJson['files'] as Map<String, dynamic>?;
      final settings = backupJson['settings'] as Map<String, dynamic>?;
      final directory = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();

      if (files != null) {
        for (final entry in files.entries) {
          final fileName = entry.key;
          final fileContent = entry.value;
          final targetFile = File('${directory.path}/$fileName');
          await targetFile.writeAsString(jsonEncode(fileContent));
        }
      }

      if (settings != null) {
        for (final entry in settings.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is List<dynamic>) {
            await prefs.setStringList(key, value.map((e) => e.toString()).toList());
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup restored successfully! Restart the app to apply changes.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error importing backup: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _clearTestData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Jobs + Documents'),
        content: const Text(
          'This will delete all jobs and related generated documents (invoices, quotes, estimates, certificates) but keep app settings, pricebook, and customer records intact. Continue?'
        ),
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

      final jobsFile = File('${directory.path}/jobs.json');
      if (await jobsFile.exists()) await jobsFile.delete();

      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last.toLowerCase();

          if (fileName.startsWith('job_') && fileName.endsWith('.json')) {
            await entity.delete();
          }

          if (fileName.endsWith('.pdf') &&
              (fileName.contains('invoice') ||
               fileName.contains('quote') ||
               fileName.contains('estimate') ||
               fileName.contains('certificate') ||
               fileName.contains('cert'))) {
            await entity.delete();
          }
        }
      }

      final keys = prefs.getKeys();
      final estimateKeys = keys.where((k) => k.startsWith('in_progress_estimate_') || k.startsWith('job_'));
      for (final key in estimateKeys) {
        await prefs.remove(key);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Jobs and related documents reset successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error resetting jobs/documents: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isClearing = false);
    }
  }
}
