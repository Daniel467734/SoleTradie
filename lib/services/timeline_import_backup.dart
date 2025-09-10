// BACKUP: Google Timeline Import Implementation
// Date: September 7, 2025
// Reason: Saving current implementation before replacement
// This file contains the complete GPS Timeline import methods that were working
// but had some issues. Kept for potential future reference or restoration.

import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Backup of Timeline Import Methods from SettingsScreen
/// These methods handled both old and new Google Timeline formats
/// including encrypted backup detection
class TimelineImportBackup {
  
  /// Import Google Timeline location data (supports both old and new formats)
  static Future<void> importGoogleTimelineData(BuildContext context) async {
    try {
      // Check for encrypted backup scenario first
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Timeline Data Import'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select your Timeline export:'),
              SizedBox(height: 16),
              Text('📁 If you have multiple JSON files with location data'),
              Text('📄 If you have "Location History.json" file'),
              Text('🔒 If you only see "Encrypted Backups.txt"'),
              SizedBox(height: 12),
              Text('Note: Google now encrypts some Timeline exports.', 
                   style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _selectTimelineFile(context);
              },
              child: const Text('Select File'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showImportError(context, 'Failed to start import: ${e.toString()}');
    }
  }

  static Future<void> _selectTimelineFile(BuildContext context) async {
    try {
      // Pick any JSON file from Timeline export
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select any JSON file from Timeline folder',
      );

      if (result != null && result.files.single.path != null) {
        final selectedFile = File(result.files.single.path!);
        
        // Show progress dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Analyzing Timeline export...'),
              ],
            ),
          ),
        );

        // Check if this is encrypted backup scenario
        final timelineFolder = selectedFile.parent;
        final hasEncryptedBackups = await _checkForEncryptedBackups(timelineFolder);
        
        if (hasEncryptedBackups) {
          Navigator.pop(context); // Close progress dialog
          _showEncryptedBackupInfo(context);
          return;
        }

        // Determine format and process accordingly
        final fileName = selectedFile.path.split('/').last.toLowerCase();
        int importedCount = 0;
        
        if (fileName == 'location history.json') {
          // Old format: Single large JSON file
          importedCount = await _processOldTimelineFormat(selectedFile);
        } else {
          // New format: Process Timeline folder structure
          importedCount = await _processNewTimelineFormat(selectedFile);
        }
        
        // Close progress dialog
        Navigator.pop(context);
        
        if (importedCount > 0) {
          _showImportSuccess(context, importedCount);
        } else {
          _showNoDataFound(context);
        }
        
      }
    } catch (e) {
      // Close progress dialog if open
      Navigator.pop(context);
      _showImportError(context, 'Import failed: ${e.toString()}');
    }
  }

  /// Check if Timeline export has encrypted backups
  static Future<bool> _checkForEncryptedBackups(Directory timelineFolder) async {
    try {
      // Check for encrypted backups text file
      final encryptedFile = File('${timelineFolder.path}/Encrypted Backups.txt');
      if (await encryptedFile.exists()) {
        return true;
      }
      
      // Check Settings.json for encrypted backup flag
      final settingsFile = File('${timelineFolder.path}/Settings.json');
      if (await settingsFile.exists()) {
        final settingsContent = await settingsFile.readAsString();
        final settings = jsonDecode(settingsContent);
        if (settings is Map && settings.containsKey('encryptedBackupsControls')) {
          final controls = settings['encryptedBackupsControls'] as Map;
          // Check if any device has encrypted backups enabled
          for (final deviceControl in controls.values) {
            if (deviceControl is Map && deviceControl['enabled'] == true) {
              return true;
            }
          }
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Process old Timeline format (Location History.json)
  static Future<int> _processOldTimelineFormat(File file) async {
    final jsonString = await file.readAsString();
    final data = jsonDecode(jsonString);
    int importedCount = 0;
    
    if (data is Map && data.containsKey('locations')) {
      final locations = data['locations'] as List;
      final prefs = await SharedPreferences.getInstance();
      final existingHistory = await _loadExistingGpsHistory();
      
      for (final location in locations) {
        if (location is Map && 
            location.containsKey('latitudeE7') && 
            location.containsKey('longitudeE7') &&
            location.containsKey('timestampMs')) {
          
          final lat = (location['latitudeE7'] as int) / 1E7;
          final lng = (location['longitudeE7'] as int) / 1E7;
          final timestamp = DateTime.fromMillisecondsSinceEpoch(
            int.parse(location['timestampMs'].toString())
          );
          
          if (_addLocationToHistory(existingHistory, lat, lng, timestamp, 'Old Timeline Import')) {
            importedCount++;
          }
        }
      }
      
      await prefs.setString('gps_visit_history', jsonEncode(existingHistory));
    }
    
    return importedCount;
  }

  /// Process new Timeline format (Timeline folder structure)
  static Future<int> _processNewTimelineFormat(File selectedFile) async {
    final prefs = await SharedPreferences.getInstance();
    final existingHistory = await _loadExistingGpsHistory();
    int importedCount = 0;
    
    // Get the Timeline folder path
    final timelineFolder = selectedFile.parent;
    
    // Look for semantic location files and records
    final files = timelineFolder.listSync().where((entity) => 
      entity is File && 
      entity.path.toLowerCase().endsWith('.json') &&
      !entity.path.toLowerCase().contains('settings')
    ).cast<File>();
    
    for (final file in files) {
      try {
        final jsonString = await file.readAsString();
        final data = jsonDecode(jsonString);
        
        // Process different new Timeline file types
        if (data is Map) {
          // Check for timeline objects with placeVisit data
          if (data.containsKey('timelineObjects')) {
            final timelineObjects = data['timelineObjects'] as List;
            
            for (final obj in timelineObjects) {
              if (obj is Map && obj.containsKey('placeVisit')) {
                final placeVisit = obj['placeVisit'] as Map;
                
                if (placeVisit.containsKey('location') && placeVisit.containsKey('duration')) {
                  final location = placeVisit['location'] as Map;
                  final duration = placeVisit['duration'] as Map;
                  
                  if (location.containsKey('latitudeE7') && 
                      location.containsKey('longitudeE7') &&
                      duration.containsKey('startTimestampMs')) {
                    
                    final lat = (location['latitudeE7'] as int) / 1E7;
                    final lng = (location['longitudeE7'] as int) / 1E7;
                    final timestamp = DateTime.fromMillisecondsSinceEpoch(
                      int.parse(duration['startTimestampMs'].toString())
                    );
                    
                    String address = 'New Timeline Import';
                    if (location.containsKey('name')) {
                      address = location['name'].toString();
                    } else if (location.containsKey('address')) {
                      address = location['address'].toString();
                    }
                    
                    if (_addLocationToHistory(existingHistory, lat, lng, timestamp, address)) {
                      importedCount++;
                    }
                  }
                }
              }
              
              // Also check for activitySegment data (travel records)
              if (obj is Map && obj.containsKey('activitySegment')) {
                final activitySegment = obj['activitySegment'] as Map;
                
                if (activitySegment.containsKey('startLocation') && 
                    activitySegment.containsKey('duration')) {
                  final startLocation = activitySegment['startLocation'] as Map;
                  final duration = activitySegment['duration'] as Map;
                  
                  if (startLocation.containsKey('latitudeE7') && 
                      startLocation.containsKey('longitudeE7') &&
                      duration.containsKey('startTimestampMs')) {
                    
                    final lat = (startLocation['latitudeE7'] as int) / 1E7;
                    final lng = (startLocation['longitudeE7'] as int) / 1E7;
                    final timestamp = DateTime.fromMillisecondsSinceEpoch(
                      int.parse(duration['startTimestampMs'].toString())
                    );
                    
                    if (_addLocationToHistory(existingHistory, lat, lng, timestamp, 'Activity Location')) {
                      importedCount++;
                    }
                  }
                }
              }
            }
          }
          
          // Check for legacy locations array in new format files
          if (data.containsKey('locations')) {
            final locations = data['locations'] as List;
            
            for (final location in locations) {
              if (location is Map && 
                  location.containsKey('latitudeE7') && 
                  location.containsKey('longitudeE7') &&
                  location.containsKey('timestampMs')) {
                
                final lat = (location['latitudeE7'] as int) / 1E7;
                final lng = (location['longitudeE7'] as int) / 1E7;
                final timestamp = DateTime.fromMillisecondsSinceEpoch(
                  int.parse(location['timestampMs'].toString())
                );
                
                if (_addLocationToHistory(existingHistory, lat, lng, timestamp, 'Timeline Location')) {
                  importedCount++;
                }
              }
            }
          }
        }
      } catch (e) {
        // Skip files that can't be parsed, continue with others
        print('Skipping file ${file.path}: $e');
      }
    }
    
    await prefs.setString('gps_visit_history', jsonEncode(existingHistory));
    return importedCount;
  }

  /// Add location to history with duplicate checking
  static bool _addLocationToHistory(List<Map<String, dynamic>> existingHistory, 
                           double lat, double lng, DateTime timestamp, String address) {
    final visitEntry = {
      'latitude': lat,
      'longitude': lng,
      'timestamp': timestamp.toIso8601String(),
      'departureTime': null,
      'duration': null,
      'address': address,
      'source': 'google_timeline_import',
    };
    
    // Check for duplicate (same location within 1 hour)
    final isDuplicate = existingHistory.any((existing) {
      if (existing['latitude'] != null && existing['longitude'] != null) {
        final existingTime = DateTime.parse(existing['timestamp']);
        final timeDiff = timestamp.difference(existingTime).abs();
        final distance = _calculateDistance(
          lat, lng, 
          existing['latitude'], existing['longitude']
        );
        return distance < 50 && timeDiff.inHours < 1; // Same location within 1 hour
      }
      return false;
    });
    
    if (!isDuplicate) {
      existingHistory.add(visitEntry);
      return true;
    }
    return false;
  }

  /// Load existing GPS history from SharedPreferences
  static Future<List<Map<String, dynamic>>> _loadExistingGpsHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      final historyList = jsonDecode(historyJson) as List;
      
      return historyList.map((entry) {
        return {
          'latitude': entry['latitude'] as double?,
          'longitude': entry['longitude'] as double?,
          'timestamp': entry['timestamp'] as String?,
          'departureTime': entry['departureTime'] as String?,
          'duration': entry['duration'] as String?,
          'address': entry['address'] as String?,
          'source': entry['source'] as String?,
        };
      }).toList();
    } catch (e) {
      print('Error loading GPS history: $e');
      return [];
    }
  }

  /// Calculate distance between two coordinates in meters
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  // Dialog methods for UI feedback
  static void _showEncryptedBackupInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Colors.orange),
            SizedBox(width: 8),
            Text('Encrypted Timeline Data'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Timeline data is encrypted and stored on Google servers.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text('What this means:'),
              SizedBox(height: 8),
              Text('🔒 Google encrypts your location history for privacy'),
              Text('📱 The data is not included in Takeout exports'),
              Text('☁️ It remains secure on Google\'s servers'),
              SizedBox(height: 16),
              Text(
                'Alternative options:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('1. 📍 Manual entry of important locations'),
              Text('2. 🎯 Use GPS tracking during jobs going forward'),
              Text('3. 📝 Export specific location data from Google Maps'),
              SizedBox(height: 16),
              Text(
                'The app\'s GPS tracking will start building your location history automatically as you visit job sites.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  static void _showImportSuccess(BuildContext context, int importedCount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Import Successful'),
          ],
        ),
        content: Text(
          'Successfully imported $importedCount location points from Google Timeline.\n\n'
          'These will now be available for GPS-based site visit tracking in your job estimates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Great!'),
          ),
        ],
      ),
    );
  }

  static void _showImportError(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Import Failed'),
          ],
        ),
        content: Text(
          '$message\n\n'
          'For new Timeline format: Select any JSON file from your Timeline folder.\n'
          'For old format: Select the "Location History.json" file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showNoDataFound(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.blue),
            SizedBox(width: 8),
            Text('No Location Data Found'),
          ],
        ),
        content: const Text(
          'No importable location data was found in the selected files.\n\n'
          'This could mean:\n'
          '• Your Timeline data is encrypted\n'
          '• Location tracking was disabled\n'
          '• Export doesn\'t contain location history\n\n'
          'You can start building location history by using GPS tracking during jobs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
