import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/estimate_item.dart' as estimate_item;
import '../../models/job.dart' as job_model;
import '../../services/address_search_service.dart';
import '../pricebook_extensive_screen.dart';

// ====================================================================
// GPS HISTORY SCREEN - Comprehensive site visit tracking
// ====================================================================

class GpsHistoryScreen extends StatefulWidget {
  final job_model.Job job;
  final Function(estimate_item.EstimateItem) onLabourAdded;

  const GpsHistoryScreen({
    super.key,
    required this.job,
    required this.onLabourAdded,
  });

  @override
  State<GpsHistoryScreen> createState() => _GpsHistoryScreenState();
}

class _GpsHistoryScreenState extends State<GpsHistoryScreen> {
  List<Map<String, dynamic>> _siteVisits = [];
  Map<String, double>? _siteCoordinates;
  bool _isLoadingHistory = false;
  bool _isLoadingLocation = false;
  bool _isSearchingAddresses = false;
  String _currentAddress = '';
  final TextEditingController _addressController = TextEditingController();
  List<AddressSearchResult> _addressSearchResults = [];
  double _proximityRadius = 50.0; // Default 50 meters
  PriceBookItem? _calLabourItem;
  bool _addressResolved = false;

  @override
  void initState() {
    super.initState();
    _currentAddress = widget.job.address ?? '';
    _addressController.text = _currentAddress;
    _initializeScreen();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  /// Clear address search results
  void _clearAddressSearch() {
    setState(() {
      _addressSearchResults = [];
    });
  }

  Future<void> _initializeScreen() async {
    // Load CAL LABOUR pricebook item
    await _loadCalLabourItem();

    // Check if address needs geocoding
    if (_currentAddress.isNotEmpty) {
      _addressResolved = await _hasGeocodedCoordinates(_currentAddress);
      if (!_addressResolved) {
        // Show address search first
        return;
      }
    }

    // Load site coordinates and history
    await _loadSiteCoordinatesAndHistory();
  }

  /// Search for addresses using the address search service
  Future<void> _searchAddresses(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _addressSearchResults = [];
      });
      return;
    }

    setState(() {
      _isSearchingAddresses = true;
    });

    try {
      final results =
          await AddressSearchService.searchAddresses(query, limit: 5);
      setState(() {
        _addressSearchResults = results;
      });
    } catch (e) {
      print('Error searching addresses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching addresses: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      setState(() {
        _isSearchingAddresses = false;
      });
    }
  }

  /// Select an address from search results and geocode it
  Future<void> _selectAddress(AddressSearchResult address) async {
    setState(() {
      _currentAddress = address.address;
      _addressController.text = address.address;
      _addressSearchResults = [];
    });

    if (address.latitude != null && address.longitude != null) {
      // Use coordinates from search result
      _siteCoordinates = {
        'lat': address.latitude!,
        'lng': address.longitude!,
      };

      setState(() {
        _addressResolved = true;
      });

      // Load visit history now that we have coordinates
      await _loadSiteVisitHistory();
    } else {
      // Fallback to geocoding
      await _geocodeAddress(address.address);
    }
  }

  Future<void> _loadCalLabourItem() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final priceBook =
            jsonList.map((e) => PriceBookItem.fromJson(e)).toList();

        _calLabourItem = priceBook.firstWhere(
          (item) => item.code == 'CAL',
          orElse: () => PriceBookItem(
            code: 'CAL',
            name: 'Labour',
            price: 85.0,
            purchasePrice: 65.0,
            unit: 'hr',
            groupCode: 'LABOUR',
            favorite: false,
            usageCount: 0,
          ),
        );
      }
    } catch (e) {
      print('Error loading CAL LABOUR item: $e');
    }
  }

  Future<bool> _hasGeocodedCoordinates(String address) async {
    try {
      final locations = await locationFromAddress(address);
      return locations.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _geocodeAddress(String address) async {
    setState(() {
      _isLoadingLocation = true;
      _addressSearchResults = []; // Clear search results
    });

    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;
        _siteCoordinates = {
          'lat': location.latitude,
          'lng': location.longitude,
        };

        // Update job address if it changed
        // Note: Job address is final, so we can't update it here
        // In a real implementation, you'd need to update the job through proper channels

        setState(() {
          _currentAddress = address;
          _addressResolved = true;
        });

        // Load visit history now that we have coordinates
        await _loadSiteVisitHistory();
      } else {
        throw Exception('No coordinates found for this address');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error geocoding address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _loadSiteCoordinatesAndHistory() async {
    if (_currentAddress.isEmpty) return;

    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Get coordinates from address
      final locations = await locationFromAddress(_currentAddress);
      if (locations.isNotEmpty) {
        final location = locations.first;
        _siteCoordinates = {
          'lat': location.latitude,
          'lng': location.longitude,
        };

        // Load visit history
        await _loadSiteVisitHistory();
      }
    } catch (e) {
      print('Error loading site coordinates: $e');
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _loadSiteVisitHistory() async {
    if (_siteCoordinates == null) return;

    setState(() {
      _isLoadingHistory = true;
      _siteVisits.clear(); // Clear any existing data
    });

    try {
      // Get current position
      Position? currentPosition;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission != LocationPermission.denied &&
              permission != LocationPermission.deniedForever) {
            currentPosition = await Geolocator.getCurrentPosition();
          }
        }
      } catch (e) {
        print('Error getting current position: $e');
      }

      // Load stored GPS history from device
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      final storedHistory = jsonDecode(historyJson) as List;

      final siteHistory = <Map<String, dynamic>>[];

      // Process stored GPS history to find visits to this address
      for (final entry in storedHistory) {
        final entryLat = entry['latitude'] as double?;
        final entryLng = entry['longitude'] as double?;
        final timestamp = entry['timestamp'] != null
            ? DateTime.parse(entry['timestamp'])
            : null;

        if (entryLat != null && entryLng != null && timestamp != null) {
          final distance = Geolocator.distanceBetween(
            entryLat,
            entryLng,
            _siteCoordinates!['lat']!,
            _siteCoordinates!['lng']!,
          );

          // Only include visits within proximity range
          if (distance <= _proximityRadius) {
            DateTime? departureTime;
            double? duration = entry['duration']?.toDouble();

            if (entry['departureTime'] != null) {
              departureTime = DateTime.parse(entry['departureTime']);
            }

            // If no departure time, calculate duration from arrival to current time (still on-site)
            if (departureTime == null && duration == null) {
              final arrivalTime = timestamp;
              final currentTime = DateTime.now();
              duration = currentTime.difference(arrivalTime).inMinutes / 60.0;
            }

            siteHistory.add({
              'arrivalTime': timestamp,
              'departureTime': departureTime,
              'duration': duration,
              'distance': distance,
              'isCurrentVisit': false,
            });
          }
        }
      }

      // Check if currently on site
      if (currentPosition != null) {
        final distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          _siteCoordinates!['lat']!,
          _siteCoordinates!['lng']!,
        );

        // If currently within range, add current visit
        if (distance <= _proximityRadius) {
          siteHistory.insert(0, {
            'arrivalTime': DateTime.now()
                .subtract(const Duration(minutes: 30)), // Estimate arrival
            'departureTime': null, // Still on site
            'duration': null,
            'distance': distance,
            'isCurrentVisit': true,
          });
        }
      }

      // Sort by most recent first
      siteHistory.sort((a, b) => (b['arrivalTime'] as DateTime)
          .compareTo(a['arrivalTime'] as DateTime));

      setState(() {
        _siteVisits = siteHistory;
      });
    } catch (e) {
      print('Error loading site visit history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading GPS history: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  Widget _buildSiteVisitsList() {
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_siteVisits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No GPS visits found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No match at this range for this address.\nIncrease the range or start GPS tracking.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // In a real app, this would start background GPS tracking
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'GPS tracking would start in background (feature to be implemented)'),
                    ),
                  );
                },
                icon: const Icon(Icons.my_location),
                label: const Text('Start GPS Tracking'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _siteVisits.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final visit = _siteVisits[index];
        final arrivalTime = visit['arrivalTime'] as DateTime?;
        final departureTime = visit['departureTime'] as DateTime?;
        final duration = visit['duration'] as double?;
        final distance = visit['distance'] as double?;
        final isCurrentVisit = visit['isCurrentVisit'] as bool? ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCurrentVisit ? Icons.location_on : Icons.history,
                      color: isCurrentVisit ? Colors.green : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isCurrentVisit ? 'Current Visit' : 'Past Visit',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (distance != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${distance.toStringAsFixed(0)}m',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (arrivalTime != null) ...[
                  Text(
                    'Arrival: ${arrivalTime.day}/${arrivalTime.month}/${arrivalTime.year} ${arrivalTime.hour}:${arrivalTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                if (departureTime != null) ...[
                  Text(
                    'Departure: ${departureTime.day}/${departureTime.month}/${departureTime.year} ${departureTime.hour}:${departureTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                if (duration != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    departureTime == null
                        ? 'Duration: ${duration.toStringAsFixed(1)} hours (still on-site)'
                        : 'Duration: ${duration.toStringAsFixed(1)} hours',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Add Labour Item: '),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _addLabourFromVisit(visit),
                          child: Text('${duration.toStringAsFixed(1)}h Labour'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _addLabourFromVisit(Map<String, dynamic> visit) {
    if (_calLabourItem == null) return;

    final arrivalTime = visit['arrivalTime'] as DateTime?;
    if (arrivalTime == null) return;

    final duration = visit['duration'] as double? ?? 0.0;
    final dateStr = '${arrivalTime.day}/${arrivalTime.month}';

    final labourItem = estimate_item.EstimateItem(
      name: 'Labour on $dateStr',
      description: 'CAL',
      unitPrice: _calLabourItem!.price,
      purchasePrice: _calLabourItem!.purchasePrice,
      quantity: duration,
      section: 'Labour',
    );

    widget.onLabourAdded(labourItem);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${duration}h labour for $dateStr'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Site History'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Address Search Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Site Address',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: _addressController,
                            decoration: InputDecoration(
                              hintText: 'Search for site address...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _isSearchingAddresses
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (value) {
                              // Debounce search to avoid too many API calls
                              Future.delayed(const Duration(milliseconds: 500),
                                  () {
                                if (value == _addressController.text) {
                                  _searchAddresses(value);
                                }
                              });
                            },
                            onSubmitted: (address) {
                              if (address.trim().isNotEmpty) {
                                _geocodeAddress(address.trim());
                              }
                            },
                          ),
                          // Address search results dropdown
                          if (_addressSearchResults.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _addressSearchResults.length,
                                itemBuilder: (context, index) {
                                  final result = _addressSearchResults[index];
                                  return ListTile(
                                    dense: true,
                                    leading:
                                        const Icon(Icons.location_on, size: 16),
                                    title: Text(
                                      result.address,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    subtitle: result.suburb != null ||
                                            result.city != null
                                        ? Text(
                                            [
                                              result.suburb,
                                              result.city,
                                              result.postcode
                                            ]
                                                .where((e) =>
                                                    e != null && e.isNotEmpty)
                                                .join(', '),
                                            style:
                                                const TextStyle(fontSize: 12),
                                          )
                                        : null,
                                    onTap: () => _selectAddress(result),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isSearchingAddresses
                          ? null
                          : () {
                              final address = _addressController.text.trim();
                              if (address.isNotEmpty) {
                                _searchAddresses(address);
                              }
                            },
                      icon: _isSearchingAddresses
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const Text('Search Addresses'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!_addressResolved && _currentAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Please search and select an address to view GPS history',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FutureBuilder<String>(
                  future: AddressSearchService.getSelectedCountry(),
                  builder: (context, snapshot) {
                    final country = snapshot.data ?? 'New Zealand';
                    return Text(
                      'Address search powered by ${country == 'New Zealand' ? 'LINZ' : 'OpenStreetMap'} for $country',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Proximity Slider Section
          if (_addressResolved)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Site Proximity Range',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: _proximityRadius,
                          min: 10.0,
                          max: 100.0,
                          divisions: 18,
                          label: '${_proximityRadius.toInt()}m',
                          onChanged: (value) {
                            setState(() {
                              _proximityRadius = value;
                            });
                          },
                          onChangeEnd: (value) {
                            _loadSiteVisitHistory();
                          },
                        ),
                      ),
                      Text(
                        '${_proximityRadius.toInt()}m',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Test Real Location Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        print(
                            '🧪 Starting real location and geocoding test...');

                        try {
                          // Test geocoding first
                          final address = _addressController.text.trim();
                          if (address.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Please enter an address first')),
                            );
                            return;
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Testing geocoding and getting your location...')),
                          );

                          // Test if address converts to coordinates
                          print('🧪 Testing geocoding for: $address');
                          final locations = await locationFromAddress(address);

                          if (locations.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '❌ Geocoding failed - address not found'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          final siteCoords = locations.first;
                          print(
                              '✅ Geocoding successful! Lat: ${siteCoords.latitude}, Lng: ${siteCoords.longitude}');

                          // Get current real device location
                          bool serviceEnabled =
                              await Geolocator.isLocationServiceEnabled();
                          if (!serviceEnabled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('❌ Please enable location services'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          LocationPermission permission =
                              await Geolocator.checkPermission();
                          if (permission == LocationPermission.denied) {
                            permission = await Geolocator.requestPermission();
                            if (permission == LocationPermission.denied) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('❌ Location permission denied'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                          }

                          final currentPosition =
                              await Geolocator.getCurrentPosition();
                          print(
                              '✅ Got current location! Lat: ${currentPosition.latitude}, Lng: ${currentPosition.longitude}');

                          // Calculate distance
                          final distance = Geolocator.distanceBetween(
                            currentPosition.latitude,
                            currentPosition.longitude,
                            siteCoords.latitude,
                            siteCoords.longitude,
                          );

                          print(
                              '📏 Distance to job site: ${distance.toStringAsFixed(1)} meters');

                          // Add current location to GPS history
                          final prefs = await SharedPreferences.getInstance();
                          final historyJson =
                              prefs.getString('gps_visit_history') ?? '[]';
                          final historyList = jsonDecode(historyJson) as List;

                          historyList.add({
                            'latitude': currentPosition.latitude,
                            'longitude': currentPosition.longitude,
                            'timestamp': DateTime.now()
                                .subtract(const Duration(hours: 1))
                                .toIso8601String(),
                            'departureTime': DateTime.now().toIso8601String(),
                            'duration': '1.0',
                            'address': 'Test location - $address',
                          });

                          await prefs.setString(
                              'gps_visit_history', jsonEncode(historyList));

                          // Reload the GPS history to show the new test entry
                          await _loadSiteVisitHistory();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '✅ Test complete!\n'
                                'Distance: ${distance.toStringAsFixed(1)}m\n'
                                'Added your location to GPS history',
                              ),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        } catch (e) {
                          print('❌ Test failed: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('❌ Test failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.science),
                      label: const Text('Test Real Location & Geocoding'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Site Visits List
          if (_addressResolved)
            Expanded(
              child: _isLoadingHistory
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading site visit history...'),
                        ],
                      ),
                    )
                  : _siteVisits.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No site visits found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Visit the site to start tracking your time',
                                style: TextStyle(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _siteVisits.length,
                          itemBuilder: (context, index) {
                            final visit = _siteVisits[index];
                            final arrivalTime =
                                visit['arrivalTime'] as DateTime?;
                            final departureTime =
                                visit['departureTime'] as DateTime?;
                            final duration =
                                visit['duration'] as double? ?? 0.0;
                            final distance =
                                visit['distance'] as double? ?? 0.0;
                            final isCurrentVisit =
                                visit['isCurrentVisit'] as bool? ?? false;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header
                                    Row(
                                      children: [
                                        Icon(
                                          isCurrentVisit
                                              ? Icons.location_on
                                              : Icons.location_history,
                                          color: isCurrentVisit
                                              ? Colors.green
                                              : Colors.blue,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          arrivalTime != null
                                              ? 'Visit on ${arrivalTime.day}/${arrivalTime.month}'
                                              : 'Site Visit',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (isCurrentVisit)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'ON SITE',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Time Details
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Arrival',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                arrivalTime != null
                                                    ? '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}'
                                                    : '—',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Departure',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                departureTime != null
                                                    ? '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}'
                                                    : isCurrentVisit
                                                        ? 'On site'
                                                        : '—',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: isCurrentVisit
                                                      ? Colors.green
                                                      : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Distance',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${distance.toInt()}m',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Duration Control
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Column(
                                        children: [
                                          const Text(
                                            'Time on Site',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          // Display duration from real GPS data (read-only)
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.blue[50],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.blue[200]!),
                                            ),
                                            child: Text(
                                              departureTime == null
                                                  ? 'Duration: ${duration.toStringAsFixed(1)} hours (still on-site)'
                                                  : 'Duration: ${duration.toStringAsFixed(1)} hours',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Add Labour Button
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: duration > 0 &&
                                                arrivalTime != null
                                            ? () => _addLabourFromVisit(visit)
                                            : null,
                                        icon: const Icon(Icons.add_task),
                                        label: Text(
                                          arrivalTime != null
                                              ? 'Add Labour (${arrivalTime.day}/${arrivalTime.month})'
                                              : 'Add Labour',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.green.shade600,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

          // Address Not Resolved State
          if (!_addressResolved)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_searching,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Address Verification Required',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please verify the site address above to view GPS history',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
