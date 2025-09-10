import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class AddressSearchResult {
  final String address;
  final double? latitude;
  final double? longitude;
  final String? suburb;
  final String? city;
  final String? region;
  final String? postcode;
  final String? country;
  final double? distanceKm; // Distance from company address

  AddressSearchResult({
    required this.address,
    this.latitude,
    this.longitude,
    this.suburb,
    this.city,
    this.region,
    this.postcode,
    this.country,
    this.distanceKm,
  });

  factory AddressSearchResult.fromJson(Map<String, dynamic> json, String countryCode) {
    switch (countryCode) {
      case 'NZ':
        return AddressSearchResult._fromNewZealandJson(json);
      default:
        return AddressSearchResult._fromGenericJson(json);
    }
  }

  factory AddressSearchResult._fromNewZealandJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List?;
    
    // Try to get the full address with house number
    final properties = json['properties'] as Map<String, dynamic>? ?? {};
    String address = properties['full_address'] ?? properties['address'] ?? '';
    
    // If the address doesn't include the house number, try to construct it
    if (address.isEmpty || !_containsNumber(address)) {
      final houseNumber = properties['house_number']?.toString() ?? 
                         properties['number']?.toString() ?? '';
      final streetName = properties['street_name'] ?? properties['road'] ?? '';
      
      if (houseNumber.isNotEmpty && streetName.isNotEmpty) {
        address = '$houseNumber $streetName';
        // Add suburb/locality if available
        final suburb = properties['suburb_locality'] ?? properties['suburb'] ?? '';
        if (suburb.isNotEmpty) {
          address += ', $suburb';
        }
      } else if (address.isEmpty) {
        address = streetName.isNotEmpty ? streetName : (properties['display_name'] ?? '');
      }
    }
    
    return AddressSearchResult(
      address: address,
      latitude: coordinates != null && coordinates.length >= 2 ? coordinates[1]?.toDouble() : null,
      longitude: coordinates != null && coordinates.length >= 2 ? coordinates[0]?.toDouble() : null,
      suburb: properties['suburb_locality'] ?? properties['suburb'],
      city: properties['city'] ?? properties['town'],
      region: properties['region'] ?? properties['state'],
      postcode: properties['postcode'],
      country: 'New Zealand',
    );
  }

  factory AddressSearchResult._fromGenericJson(Map<String, dynamic> json) {
    // Try to extract house number from display name for OSM results
    String displayName = json['display_name'] ?? json['formatted'] ?? '';
    final address = json['address'] as Map<String, dynamic>? ?? {};
    
    // Try to get house number and road to construct a better address
    final houseNumber = address['house_number']?.toString() ?? '';
    final road = address['road'] ?? '';
    
    String finalAddress = displayName;
    if (houseNumber.isNotEmpty && road.isNotEmpty) {
      final suburb = address['suburb'] ?? address['neighbourhood'] ?? '';
      final city = address['city'] ?? address['town'] ?? address['village'] ?? '';
      
      finalAddress = '$houseNumber $road';
      if (suburb.isNotEmpty) finalAddress += ', $suburb';
      if (city.isNotEmpty) finalAddress += ', $city';
    }
    
    return AddressSearchResult(
      address: finalAddress,
      latitude: double.tryParse(json['lat']?.toString() ?? ''),
      longitude: double.tryParse(json['lon']?.toString() ?? ''),
      suburb: address['suburb'] ?? address['neighbourhood'],
      city: address['city'] ?? address['town'] ?? address['village'],
      region: address['state'] ?? address['region'],
      postcode: address['postcode'],
      country: address['country'] ?? '',
    );
  }
  
  // Helper method to check if address contains a number
  static bool _containsNumber(String text) {
    return RegExp(r'\d').hasMatch(text);
  }

  // Create a copy with distance calculated
  AddressSearchResult withDistance(double? distance) {
    return AddressSearchResult(
      address: address,
      latitude: latitude,
      longitude: longitude,
      suburb: suburb,
      city: city,
      region: region,
      postcode: postcode,
      country: country,
      distanceKm: distance,
    );
  }
}

class AddressSearchService {
  /// Get the selected country from settings
  static Future<String> getSelectedCountry() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_country') ?? 'New Zealand';
  }

  /// Get company address coordinates for proximity sorting
  static Future<Map<String, double>?> getCompanyCoordinates() async {
    final prefs = await SharedPreferences.getInstance();
    final companyAddress = prefs.getString('company_address');
    
    if (companyAddress == null || companyAddress.trim().isEmpty) {
      return null;
    }
    
    // Try to get cached coordinates first
    final cachedLat = prefs.getDouble('company_latitude');
    final cachedLon = prefs.getDouble('company_longitude');
    
    if (cachedLat != null && cachedLon != null) {
      return {'latitude': cachedLat, 'longitude': cachedLon};
    }
    
    // Geocode the company address if coordinates aren't cached
    try {
      final result = await geocodeAddress(companyAddress);
      if (result?.latitude != null && result?.longitude != null) {
        // Cache the coordinates
        await prefs.setDouble('company_latitude', result!.latitude!);
        await prefs.setDouble('company_longitude', result.longitude!);
        return {'latitude': result.latitude!, 'longitude': result.longitude!};
      }
    } catch (e) {
      print('Error geocoding company address: $e');
    }
    
    return null;
  }

  /// Calculate distance between two points using Haversine formula
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth's radius in kilometers
    
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
  
  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Search for addresses based on the selected country
  static Future<List<AddressSearchResult>> searchAddresses(String query, {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    
    final country = await getSelectedCountry();
    List<AddressSearchResult> results;
    
    switch (country) {
      case 'New Zealand':
        results = await _searchNewZealandAddresses(query, limit);
        break;
      default:
        results = await _searchOpenStreetMapAddresses(query, country, limit);
        break;
    }

    // Sort by proximity to company address if available
    final companyCoords = await getCompanyCoordinates();
    if (companyCoords != null) {
      final companyLat = companyCoords['latitude']!;
      final companyLon = companyCoords['longitude']!;
      
      // Calculate distances and sort
      results = results.map((result) {
        if (result.latitude != null && result.longitude != null) {
          final distance = calculateDistance(
            companyLat, companyLon, 
            result.latitude!, result.longitude!
          );
          return result.withDistance(distance);
        }
        return result.withDistance(null);
      }).toList();
      
      // Sort by distance (closest first), with addresses without coordinates at the end
      results.sort((a, b) {
        if (a.distanceKm == null && b.distanceKm == null) return 0;
        if (a.distanceKm == null) return 1;
        if (b.distanceKm == null) return -1;
        return a.distanceKm!.compareTo(b.distanceKm!);
      });
    }
    
    return results;
  }

  /// Search addresses using New Zealand's LINZ API (free)
  static Future<List<AddressSearchResult>> _searchNewZealandAddresses(String query, int limit) async {
    try {
      // LINZ Address Search API - free for up to 1000 requests per day
      final encodedQuery = Uri.encodeComponent(query);
      final url = 'https://api.linz.govt.nz/v1/search?q=$encodedQuery&count=$limit&format=json';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'SoleTradie Mobile App',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = data['features'] as List? ?? [];
        
        return features
            .map((feature) => AddressSearchResult.fromJson(feature, 'NZ'))
            .where((result) => result.address.isNotEmpty)
            .toList();
      } else if (response.statusCode == 429) {
        // Rate limit exceeded, fallback to OpenStreetMap
        return _searchOpenStreetMapAddresses(query, 'New Zealand', limit);
      } else {
        print('LINZ API error: ${response.statusCode} - ${response.body}');
        // Fallback to OpenStreetMap for New Zealand
        return _searchOpenStreetMapAddresses(query, 'New Zealand', limit);
      }
    } catch (e) {
      print('Error searching NZ addresses: $e');
      // Fallback to OpenStreetMap
      return _searchOpenStreetMapAddresses(query, 'New Zealand', limit);
    }
  }

  /// Search addresses using OpenStreetMap Nominatim API (free, fallback)
  static Future<List<AddressSearchResult>> _searchOpenStreetMapAddresses(String query, String country, int limit) async {
    try {
      final encodedQuery = Uri.encodeComponent('$query, $country');
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=$limit&addressdetails=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'SoleTradie Mobile App (contact: developer@example.com)',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        return data
            .map((item) => AddressSearchResult.fromJson(item, 'OSM'))
            .where((result) => result.address.isNotEmpty)
            .toList();
      } else {
        print('OpenStreetMap API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error searching addresses via OpenStreetMap: $e');
      return [];
    }
  }

  /// Get coordinates for a specific address (geocoding)
  static Future<AddressSearchResult?> geocodeAddress(String address) async {
    final results = await searchAddresses(address, limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  /// Validate if an address can be geocoded
  static Future<bool> canGeocodeAddress(String address) async {
    final result = await geocodeAddress(address);
    return result != null && result.latitude != null && result.longitude != null;
  }
}
