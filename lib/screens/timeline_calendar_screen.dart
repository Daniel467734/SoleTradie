import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pricebook_extensive_screen.dart' show PriceBookItem;

class TimelineCalendarScreen extends StatefulWidget {
  final Map<String, dynamic>? targetEstimate;
  
  const TimelineCalendarScreen({super.key, this.targetEstimate});

  @override
  State<TimelineCalendarScreen> createState() => _TimelineCalendarScreenState();
}

class _TimelineCalendarScreenState extends State<TimelineCalendarScreen> {
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> locationHistory = [];
  double proximitySlider = 50.0; // Default 50 meters
  
  @override
  void initState() {
    super.initState();
    _loadLocationHistory();
  }

  Future<void> _loadLocationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      final historyList = jsonDecode(historyJson) as List;
      
      setState(() {
        locationHistory = historyList.map((entry) {
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
      });
    } catch (e) {
      print('Error loading location history: $e');
    }
  }

  List<Map<String, dynamic>> _getLocationsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return locationHistory.where((location) {
      if (location['timestamp'] == null) return false;
      try {
        final locationTime = DateTime.parse(location['timestamp']);
        return locationTime.isAfter(startOfDay) && locationTime.isBefore(endOfDay);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  void _goToPreviousDay() {
    setState(() {
      selectedDate = selectedDate.subtract(const Duration(days: 1));
    });
  }

  void _goToNextDay() {
    setState(() {
      selectedDate = selectedDate.add(const Duration(days: 1));
    });
  }

  void _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final selectedDay = DateTime(date.year, date.month, date.day);

    if (selectedDay == today) {
      return 'Today';
    } else if (selectedDay == yesterday) {
      return 'Yesterday';
    } else {
      return '${_getWeekday(date.weekday)}, ${_getMonth(date.month)} ${date.day}';
    }
  }

  String _getWeekday(int weekday) {
    const weekdays = [
      '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return weekdays[weekday];
  }

  String _getMonth(int month) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month];
  }

  String _formatTime(String timestamp) {
    try {
      final time = DateTime.parse(timestamp);
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (e) {
      return 'Unknown';
    }
  }

  String _calculateDuration(Map<String, dynamic> location) {
    try {
      if (location['departureTime'] != null) {
        final arrival = DateTime.parse(location['timestamp']);
        final departure = DateTime.parse(location['departureTime']);
        final duration = departure.difference(arrival);
        final hours = duration.inMinutes / 60;
        return '${hours.toStringAsFixed(1)}h';
      }
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showLocationHistory(Map<String, dynamic> selectedLocation) {
    final double selectedLat = selectedLocation['latitude'] ?? 0.0;
    final double selectedLng = selectedLocation['longitude'] ?? 0.0;

    // Find all locations within proximity
    final nearbyVisits = locationHistory.where((location) {
      if (location['latitude'] == null || location['longitude'] == null) return false;
      
      final distance = _calculateDistance(
        selectedLat, selectedLng,
        location['latitude'], location['longitude']
      );
      return distance <= proximitySlider;
    }).toList();

    // Sort by most recent
    nearbyVisits.sort((a, b) {
      try {
        final timeA = DateTime.parse(a['timestamp']);
        final timeB = DateTime.parse(b['timestamp']);
        return timeB.compareTo(timeA); // Most recent first
      } catch (e) {
        return 0;
      }
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Site Visit History', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                selectedLocation['address'] ?? 'Unknown Location',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Proximity:', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: proximitySlider,
                          min: 10.0,
                          max: 100.0,
                          divisions: 18,
                          onChanged: (value) {
                            setDialogState(() {
                              proximitySlider = value;
                            });
                            setState(() {
                              proximitySlider = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${proximitySlider.toInt()}m',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: nearbyVisits.isEmpty
                ? const Center(child: Text('No visits found within proximity'))
                : ListView.builder(
                    itemCount: nearbyVisits.length,
                    itemBuilder: (context, index) {
                      final visit = nearbyVisits[index];
                      return _buildVisitItem(visit);
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitItem(Map<String, dynamic> visit) {
    final timestamp = visit['timestamp'] ?? '';
    final address = visit['address'] ?? 'Unknown Location';
    
    // Calculate time on site, defaulting to rounded hours
    double timeOnSite = 1.0; // Default 1 hour
    try {
      if (visit['departureTime'] != null) {
        final arrival = DateTime.parse(visit['timestamp']);
        final departure = DateTime.parse(visit['departureTime']);
        final duration = departure.difference(arrival).inMinutes;
        timeOnSite = (duration / 60.0);
        // Round to nearest 0.5 hour
        timeOnSite = (timeOnSite * 2).round() / 2.0;
      }
    } catch (e) {
      // Keep default 1.0
    }

    return StatefulBuilder(
      builder: (context, setItemState) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, color: Colors.blue, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, color: Colors.grey[600], size: 14),
                  const SizedBox(width: 4),
                  Text(
                    timestamp.isNotEmpty 
                        ? _formatDateTime(timestamp)
                        : 'Unknown time',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Time on site:', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: timeOnSite > 0.5 ? () {
                          setItemState(() {
                            timeOnSite = math.max(0.5, timeOnSite - 0.5);
                          });
                        } : null,
                        icon: const Icon(Icons.remove),
                        iconSize: 20,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${timeOnSite}h',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setItemState(() {
                            timeOnSite += 0.5;
                          });
                        },
                        icon: const Icon(Icons.add),
                        iconSize: 20,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _addLabourItem(timeOnSite, address, timestamp),
                  icon: const Icon(Icons.work, size: 18),
                  label: const Text('Add to Labour'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(String timestamp) {
    try {
      final time = DateTime.parse(timestamp);
      final date = '${time.day}/${time.month}/${time.year}';
      final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      return '$date at $timeStr';
    } catch (e) {
      return 'Unknown time';
    }
  }

  Future<void> _addLabourItem(double hours, String address, String timestamp) async {
    try {
      // Load pricebook and find CAL: Labour
      final prefs = await SharedPreferences.getInstance();
      final priceBookJson = prefs.getString('price_book') ?? '[]';
      final priceBookData = jsonDecode(priceBookJson) as List;
      
      // Find CAL: Labour from pricebook
      PriceBookItem? calLabourItem;
      try {
        final calData = priceBookData.firstWhere(
          (item) => item['code'] == 'CAL',
        );
        calLabourItem = PriceBookItem(
          code: calData['code'] ?? 'CAL',
          name: calData['name'] ?? 'Labour',
          unit: calData['unit'] ?? 'HR',
          groupCode: calData['groupCode'] ?? 'LABOUR',
          price: (calData['price'] as num?)?.toDouble() ?? 90.0,
          purchasePrice: (calData['purchasePrice'] as num?)?.toDouble() ?? 0.0,
          favorite: false,
        );
      } catch (e) {
        // Default CAL labour item if not found
        calLabourItem = PriceBookItem(
          code: 'CAL',
          name: 'Labour',
          unit: 'HR',
          groupCode: 'LABOUR',
          price: 90.0,
          purchasePrice: 0.0,
          favorite: false,
        );
      }

      // Get date from timestamp for the item name
      DateTime date;
      try {
        date = DateTime.parse(timestamp);
      } catch (e) {
        date = DateTime.now();
      }

      final itemName = 'Labour ${date.day}/${date.month}';

      // Create the labour item data to pass back to the estimate builder
      final labourItemData = {
        'code': calLabourItem.code,
        'name': itemName,
        'quantity': hours,
        'unit': calLabourItem.unit,
        'price': calLabourItem.price,
        'purchasePrice': calLabourItem.purchasePrice,
        'subsection': 'Labour',
        'groupCode': calLabourItem.groupCode,
      };

      // Close the history dialog and pass the labour item back to the estimate builder
      Navigator.pop(context); // Close the visit dialog
      Navigator.pop(context, labourItemData); // Close the timeline screen and pass the data

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add labour item: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    final locationsForDate = _getLocationsForDate(selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Timeline'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Date navigation header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              children: [
                IconButton(
                  onPressed: _goToPreviousDay,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _selectDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(selectedDate),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: selectedDate.isBefore(DateTime.now()) ? _goToNextDay : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),

          // Proximity slider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Proximity Filter: '),
                Expanded(
                  child: Slider(
                    value: proximitySlider,
                    min: 10.0,
                    max: 100.0,
                    divisions: 18,
                    label: '${proximitySlider.toInt()}m',
                    onChanged: (value) {
                      setState(() {
                        proximitySlider = value;
                      });
                    },
                  ),
                ),
                Text('${proximitySlider.toInt()}m'),
              ],
            ),
          ),

          // Locations list
          Expanded(
            child: locationsForDate.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No locations found for ${_formatDate(selectedDate)}',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try selecting a different date or enable GPS tracking',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: locationsForDate.length,
                    itemBuilder: (context, index) {
                      final location = locationsForDate[index];
                      final timestamp = location['timestamp'] ?? '';
                      final address = location['address'] ?? 'Unknown Location';
                      final duration = _calculateDuration(location);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => _showLocationHistory(location),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.blue[100],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    Icons.location_on,
                                    color: Colors.blue[700],
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        address,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Arrived: ${_formatTime(timestamp)}',
                                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                          ),
                                          if (duration != 'Unknown') ...[
                                            const SizedBox(width: 16),
                                            Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Duration: $duration',
                                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[400],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
