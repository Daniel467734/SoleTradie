part of '../estimate_builder_screen.dart';

extension _EstimateBuilderGpsPersistenceExt on _EstimateBuilderScreenState {
  /// Get coordinates from address using geocoding
  Future<Map<String, double>?> _getCoordinatesFromAddress(
      String address) async {
    try {
      // Use geocoding package to convert address to coordinates
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return {
          'lat': locations.first.latitude,
          'lng': locations.first.longitude
        };
      }
      return null;
    } catch (e) {
      print('Error geocoding address: $e');
      return null;
    }
  }

  /// Load GPS history from local storage
  Future<List<Map<String, dynamic>>> _loadGpsHistoryFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      final historyList = jsonDecode(historyJson) as List;

      print(
          'Loading GPS history from storage: ${historyList.length} entries found');

      final result = historyList.map((entry) {
        return {
          'latitude': entry['latitude'] as double?,
          'longitude': entry['longitude'] as double?,
          'timestamp': entry['timestamp'] != null
              ? DateTime.parse(entry['timestamp'])
              : null,
          'departureTime': entry['departureTime'] != null
              ? DateTime.parse(entry['departureTime'])
              : null,
          'duration': entry['duration'] as String?,
          'address': entry['address'] as String?,
        };
      }).toList();

      print('Converted ${result.length} entries for timeline display');
      return result;
    } catch (e) {
      print('Error loading GPS history: $e');
      return [];
    }
  }

  /// Save GPS visit to storage
  Future<void> _saveGpsVisit({
    required double latitude,
    required double longitude,
    required DateTime arrivalTime,
    DateTime? departureTime,
    String? duration,
    String? address,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingHistory = await _loadGpsHistoryFromStorage();

      // Add new visit
      existingHistory.add({
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': arrivalTime.toIso8601String(),
        'departureTime': departureTime?.toIso8601String(),
        'duration': duration,
        'address': address,
      });

      // Keep only last 100 visits to prevent storage bloat
      if (existingHistory.length > 100) {
        existingHistory.removeRange(0, existingHistory.length - 100);
      }

      await prefs.setString('gps_visit_history', jsonEncode(existingHistory));
    } catch (e) {
      print('Error saving GPS visit: $e');
    }
  }
}
