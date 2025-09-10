import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/estimate_item.dart' as estimate_item;
import '../screens/pricebook_screen.dart';

class GpsService {
  static double _gpsDistanceRange = 50.0; // Default range in meters
  
  /// Show GPS site history with automatic location detection
  static Future<void> showGpsSiteHistoryWithLocation(
    BuildContext context,
    String? jobAddress,
    String jobId,
    List<PriceBookItem> priceBook,
    Function(estimate_item.EstimateItem) onAddLabourItem,
    Function(String) getOrCreateLabourSection,
  ) async {
    Position? currentPosition;
    
    try {
      // Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied, we cannot request permissions.');
      } else {
        // Get current position
        currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        print('📍 Current position: ${currentPosition.latitude}, ${currentPosition.longitude}');
      }
    } catch (e) {
      print('Error getting current position: $e');
    }
    
    // Show the dialog with the obtained position
    return showGpsSiteHistory(
      context,
      jobAddress,
      jobId,
      currentPosition,
      priceBook,
      onAddLabourItem,
      getOrCreateLabourSection,
    );
  }
  
  /// Show enhanced GPS site history with modern UI
  static Future<void> showGpsSiteHistory(
    BuildContext context,
    String? jobAddress,
    String jobId,
    Position? currentPosition,
    List<PriceBookItem> priceBook,
    Function(estimate_item.EstimateItem) onAddLabourItem,
    Function(String) getOrCreateLabourSection,
  ) async {
    try {
      final siteHistory = await _getSiteVisitHistory(jobAddress, currentPosition, context);
      
      if (!context.mounted) return;
      
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue),
                const SizedBox(width: 8),
                const Expanded(child: Text('GPS Site Visit History')),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () async {
                    await _showGpsSettings(context, setDialogState);
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              height: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Site info card
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.business, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Site: ${jobAddress ?? "Address not set"}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Detection range info
                  Text(
                    'Detection Range: ${_gpsDistanceRange.round()}m',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Visit history list
                  Expanded(
                    child: siteHistory.isEmpty 
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_off, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                'No site visits found',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: siteHistory.length,
                          itemBuilder: (context, index) {
                            final visit = siteHistory[index];
                            final isCurrentVisit = visit['isCurrentVisit'] == true;
                            
                            return Card(
                              elevation: isCurrentVisit ? 4 : 1,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header row
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: isCurrentVisit ? Colors.green : Colors.blue,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            isCurrentVisit ? Icons.location_on : Icons.location_history,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            isCurrentVisit ? 'Current Visit' : 'Visit ${index + 1}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isCurrentVisit ? Colors.green : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (visit['distance'] != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${(visit['distance'] as double).toStringAsFixed(0)}m',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    
                                    // Time information
                                    if (visit['arrivalTime'] != null)
                                      _buildTimeRow(Icons.login, 'Arrived', visit['arrivalTime']),
                                    if (visit['departureTime'] != null)
                                      _buildTimeRow(Icons.logout, 'Departed', visit['departureTime'])
                                    else if (isCurrentVisit)
                                      _buildTimeRow(Icons.access_time, 'On site since', visit['arrivalTime']),
                                    
                                    // Duration with time tracker
                                    if (visit['duration'] != null) ...[
                                      const SizedBox(height: 4),
                                      _buildDurationRow(
                                        visit, 
                                        setDialogState, 
                                        priceBook, 
                                        onAddLabourItem, 
                                        getOrCreateLabourSection
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () => _setCurrentLocationAsSite(jobId, jobAddress, currentPosition),
                child: const Text('Set Current Location'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Error showing GPS site history: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading GPS history: $e')),
        );
      }
    }
  }

  /// Build time information row
  static Widget _buildTimeRow(IconData icon, String label, DateTime? time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            _formatTime(time),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build duration row with time tracker controls
  static Widget _buildDurationRow(
    Map<String, dynamic> visit, 
    StateSetter setDialogState,
    List<PriceBookItem> priceBook,
    Function(estimate_item.EstimateItem) onAddLabourItem,
    Function(String) getOrCreateLabourSection,
  ) {
    final duration = visit['duration'] as double;
    final date = visit['arrivalTime'] as DateTime;
    
    return Row(
      children: [
        Icon(Icons.timer, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          'Duration: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decrease button
              InkWell(
                onTap: duration > 0.5 ? () {
                  visit['duration'] = duration - 0.5;
                  setDialogState(() {});
                } : null,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: duration > 0.5 ? Colors.blue : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Icon(
                    Icons.remove,
                    size: 10,
                    color: duration > 0.5 ? Colors.white : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              
              // Duration display
              Text(
                '${duration.toStringAsFixed(1)}h',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              
              // Increase button
              InkWell(
                onTap: () {
                  visit['duration'] = duration + 0.5;
                  setDialogState(() {});
                },
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        
        // Add labour button
        ElevatedButton(
          onPressed: () => _addLabourItemFromGPS(
            duration, 
            date, 
            priceBook, 
            onAddLabourItem, 
            getOrCreateLabourSection
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
          ),
          child: const Text(
            'Add Labour',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  /// Show GPS settings dialog
  static Future<void> _showGpsSettings(BuildContext context, StateSetter parentSetState) async {
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('GPS Detection Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Detection Range'),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('5m'),
                  Expanded(
                    child: Slider(
                      value: _gpsDistanceRange,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      label: '${_gpsDistanceRange.round()}m',
                      onChanged: (value) {
                        setDialogState(() {
                          _gpsDistanceRange = value;
                        });
                        parentSetState(() {});
                      },
                    ),
                  ),
                  const Text('100m'),
                ],
              ),
              Text(
                'Current: ${_gpsDistanceRange.round()}m',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  /// Get site visit history based on GPS proximity to job address
  static Future<List<Map<String, dynamic>>> _getSiteVisitHistory(String? address, Position? currentPosition, BuildContext context) async {
    List<Map<String, dynamic>> visitHistory = [];
    
    // If no address is set, return empty history
    if (address == null || address.isEmpty) {
      return visitHistory;
    }
    
    try {
      // Get site coordinates using geocoding
      final siteCoordinates = await _getCoordinatesFromAddress(address, context);
      if (siteCoordinates == null) return visitHistory;
      
      // Check current location
      if (currentPosition != null) {
        final currentDistance = _calculateDistance(
          currentPosition.latitude,
          currentPosition.longitude,
          siteCoordinates['lat']!,
          siteCoordinates['lng']!,
        );
        
        // Check if currently on site (within specified range)
        final isCurrentlyOnSite = currentDistance <= _gpsDistanceRange;
        
        if (isCurrentlyOnSite) {
          visitHistory.add({
            'arrivalTime': DateTime.now().subtract(const Duration(hours: 1)), // Estimate
            'departureTime': null,
            'duration': null,
            'distance': currentDistance,
            'isCurrentVisit': true,
          });
        }
      }
      
      // TODO: Load historical GPS tracking data from persistent storage
      // In a real implementation, this would come from stored GPS tracking data
      // that is continuously recorded when the app detects proximity to job sites
      
    } catch (e) {
      print('Error getting site visit history: $e');
    }
    
    // Sort by most recent first
    visitHistory.sort((a, b) {
      final aTime = a['arrivalTime'] as DateTime?;
      final bTime = b['arrivalTime'] as DateTime?;
      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime);
    });
    
    return visitHistory;
  }

  /// Add a labour item from GPS history
  static Future<void> _addLabourItemFromGPS(
    double hours, 
    DateTime date,
    List<PriceBookItem> priceBook,
    Function(estimate_item.EstimateItem) onAddLabourItem,
    Function(String) getOrCreateLabourSection,
  ) async {
    // Find CAL item in pricebook
    final calItem = priceBook.firstWhere(
      (item) => item.code == 'CAL',
      orElse: () => PriceBookItem(
        code: 'CAL',
        name: 'Labour',
        unit: 'HR',
        groupCode: 'LABOUR',
        price: 90.0,
        purchasePrice: 0.0,
        favorite: false,
        markupPercent: 0.0,
        markupOverridden: false,
        origin: 'default',
        usageCount: 0,
        percentageChanged: 0.0,
      ),
    );

    // Format date as day/month (no year)
    final formattedDate = '${date.day}/${date.month}';
    
    // Create labour item
    final labourItem = estimate_item.EstimateItem(
      name: 'Labour - $formattedDate',
      description: 'Site visit recorded via GPS',
      unitPrice: calItem.price,
      quantity: hours,
      purchasePrice: calItem.purchasePrice,
      section: getOrCreateLabourSection('Labour'),
    );

    onAddLabourItem(labourItem);
  }

  /// Get coordinates from address using geocoding with fallback dialog for incomplete addresses
  static Future<Map<String, double>?> _getCoordinatesFromAddress(String address, [BuildContext? context]) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return {
          'lat': locations.first.latitude,
          'lng': locations.first.longitude
        };
      }
      return null;
    } catch (e) {
      print('Error geocoding address "$address": $e');
      
      // If we have a context, show dialog to get more complete address
      if (context != null && context.mounted) {
        final result = await _showAddressCompletionDialog(context, address);
        if (result != null && result['coordinates'] != null) {
          return result['coordinates'] as Map<String, double>;
        }
      }
      
      return null;
    }
  }

  /// Show dialog to complete incomplete address information
  static Future<Map<String, dynamic>?> _showAddressCompletionDialog(BuildContext context, String originalAddress) async {
    final TextEditingController addressController = TextEditingController(text: originalAddress);
    Map<String, double>? coordinates;
    String? correctedAddress;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.location_on, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Complete Address'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Could not find location for:',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Text(
                        '"$originalAddress"',
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Please add more details (city, state, country):',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        hintText: 'e.g., 123 Main St, Wellington, New Zealand',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.edit_location),
                        helperText: 'Include city, state/region, and country for best results',
                        helperMaxLines: 2,
                      ),
                      maxLines: 2,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lightbulb, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tip: More specific addresses work better. Include street number, city, and country.',
                              style: TextStyle(fontSize: 12, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Skip'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final newAddress = addressController.text.trim();
                    if (newAddress.isNotEmpty && newAddress != originalAddress) {
                      // Try geocoding the updated address
                      try {
                        final locations = await locationFromAddress(newAddress);
                        if (locations.isNotEmpty) {
                          coordinates = {
                            'lat': locations.first.latitude,
                            'lng': locations.first.longitude
                          };
                          correctedAddress = newAddress;
                          
                          // Show success message
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Location found: $newAddress'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          
                          Navigator.of(context).pop(true);
                        } else {
                          // Still no results
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Still could not find location. Try adding more details.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error finding location: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Find Location'),
                ),
              ],
            );
          },
        );
      },
    );
    
    // Return both coordinates and corrected address
    if (result == true && coordinates != null) {
      return {
        'coordinates': coordinates,
        'correctedAddress': correctedAddress,
      };
    }
    
    return null;
  }

  /// Calculate distance between two coordinates in meters
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Format time for display
  static String _formatTime(DateTime? time) {
    if (time == null) return 'N/A';
    return '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Set current location as the site location for future GPS tracking
  static Future<void> _setCurrentLocationAsSite(String jobId, String? address, Position? currentPosition) async {
    try {
      if (currentPosition != null) {
        // Save current position as site location for this job
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('site_location_$jobId', jsonEncode({
          'lat': currentPosition.latitude,
          'lng': currentPosition.longitude,
          'address': address,
          'timestamp': DateTime.now().toIso8601String(),
        }));
      }
    } catch (e) {
      print('Error setting location: $e');
    }
  }

  /// Convert coordinates to human-readable address using reverse geocoding
  static Future<String?> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        List<String> addressParts = [];
        
        if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          addressParts.add(place.administrativeArea!);
        }
        
        if (addressParts.isNotEmpty) {
          return addressParts.join(', ');
        }
      }
    } catch (e) {
      print('Geocoding failed for $lat, $lng: $e');
    }
    return null;
  }

  /// Add current location to GPS history
  static Future<void> addCurrentLocationToHistory() async {
    try {
      // Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return;
      }
      
      // Get current position
      Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      // Get address from coordinates
      String? address = await _getAddressFromCoordinates(
        currentPosition.latitude, 
        currentPosition.longitude
      );
      
      // Create GPS history entry
      Map<String, dynamic> gpsEntry = {
        'latitude': currentPosition.latitude,
        'longitude': currentPosition.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'address': address ?? 'Current Location ${currentPosition.latitude.toStringAsFixed(6)}, ${currentPosition.longitude.toStringAsFixed(6)}',
        'visit_confidence': 'HIGH',
        'source': 'live_tracking',
        'accuracy': currentPosition.accuracy,
      };
      
      // Store in SharedPreferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? existingData = prefs.getString('gps_visit_history');
      List<Map<String, dynamic>> existingHistory = [];
      
      if (existingData != null) {
        try {
          List<dynamic> decoded = json.decode(existingData);
          existingHistory = decoded.cast<Map<String, dynamic>>();
        } catch (e) {
          print('Error parsing existing GPS history: $e');
        }
      }
      
      // Add new entry at the beginning for newest first
      existingHistory.insert(0, gpsEntry);
      
      // Save updated data
      await prefs.setString('gps_visit_history', json.encode(existingHistory));
      
      print('✅ Added current location to GPS history: ${gpsEntry['address']}');
      
    } catch (e) {
      print('Error adding current location to history: $e');
    }
  }
}
