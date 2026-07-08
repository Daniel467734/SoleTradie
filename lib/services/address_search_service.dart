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
    final properties = json['properties'] as Map<String, dynamic>? ?? {};

    final houseNumber = properties['house_number']?.toString() ?? properties['number']?.toString() ?? '';
    final streetName = properties['street_name'] ?? properties['road'] ?? properties['thoroughfare'] ?? '';
    final city = properties['city'] ?? properties['town'] ?? '';
    final suburb = properties['suburb_locality'] ?? properties['suburb'] ?? '';

    String address = '';
    if (houseNumber.isNotEmpty && streetName.isNotEmpty) {
      address = '$houseNumber $streetName';
      if (city.isNotEmpty) {
        address += ', $city';
      } else if (suburb.isNotEmpty) {
        address += ', $suburb';
      }
    }

    if (address.isEmpty) {
      final rawAddress = properties['full_address'] ?? properties['address'] ?? properties['display_name'] ?? '';
      address = _shortAddress(rawAddress);
    }

    if (address.isEmpty) {
      address = _shortAddress(properties['display_name'] ?? '');
    }

    if (address.isEmpty && houseNumber.isNotEmpty && streetName.isNotEmpty) {
      address = '$houseNumber $streetName';
      if (city.isNotEmpty) {
        address += ', $city';
      } else if (suburb.isNotEmpty) {
        address += ', $suburb';
      }
    }

    return AddressSearchResult(
      address: address,
      latitude: coordinates != null && coordinates.length >= 2 ? coordinates[1]?.toDouble() : null,
      longitude: coordinates != null && coordinates.length >= 2 ? coordinates[0]?.toDouble() : null,
      suburb: suburb,
      city: city,
      region: properties['region'] ?? properties['state'],
      postcode: properties['postcode'],
      country: 'New Zealand',
    );
  }

  factory AddressSearchResult._fromGenericJson(Map<String, dynamic> json) {
    String displayName = json['display_name'] ?? json['formatted'] ?? '';
    final address = json['address'] as Map<String, dynamic>? ?? {};

    final houseNumber = address['house_number']?.toString() ?? '';
    final road = address['road'] ?? address['residential'] ?? address['pedestrian'] ?? '';
    final suburb = address['suburb'] ?? address['neighbourhood'] ?? '';
    final city = address['city'] ?? address['town'] ?? address['village'] ?? '';

    String finalAddress = '';
    if (houseNumber.isNotEmpty && road.isNotEmpty) {
      finalAddress = '$houseNumber $road';
      if (city.isNotEmpty) {
        finalAddress += ', $city';
      } else if (suburb.isNotEmpty) {
        finalAddress += ', $suburb';
      }
    } else if (road.isNotEmpty) {
      finalAddress = road;
      if (city.isNotEmpty) {
        finalAddress += ', $city';
      } else if (suburb.isNotEmpty) {
        finalAddress += ', $suburb';
      }
    }

    if (finalAddress.isEmpty) {
      finalAddress = _shortAddress(displayName);
    }

    return AddressSearchResult(
      address: finalAddress,
      latitude: double.tryParse(json['lat']?.toString() ?? ''),
      longitude: double.tryParse(json['lon']?.toString() ?? ''),
      suburb: suburb,
      city: city,
      region: address['state'] ?? address['region'],
      postcode: address['postcode'],
      country: address['country'] ?? '',
    );
  }

  static String _shortAddress(String value) {
    var trimmed = value.trim();
    final removeMarkers = ['New Zealand', 'Aotearoa'];
    for (final marker in removeMarkers) {
      if (trimmed.endsWith(marker)) {
        trimmed = trimmed.substring(0, trimmed.length - marker.length).trim();
      }
      if (trimmed.endsWith(',')) {
        trimmed = trimmed.substring(0, trimmed.length - 1).trim();
      }
    }

    final parts = trimmed.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    if (parts.length <= 3) {
      return parts.join(', ');
    }
    return parts.take(3).join(', ');
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
      final uri = Uri.https(
        'api.linz.govt.nz',
        '/v1/search',
        {
          'q': query,
          'count': limit.toString(),
          'format': 'json',
        },
      );
      
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'SoleTradie Mobile App',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('LINZ API timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = data['features'] as List? ?? [];
        
        return features
            .map((feature) => AddressSearchResult.fromJson(feature, 'NZ'))
            .where((result) => result.address.isNotEmpty)
            .toList();
      } else if (response.statusCode == 429) {
        print('LINZ API rate limit reached, falling back to OpenStreetMap');
        return _searchOpenStreetMapAddresses(query, 'New Zealand', limit);
      } else {
        print('LINZ API error: ${response.statusCode} - ${response.body}');
        return _searchOpenStreetMapAddresses(query, 'New Zealand', limit);
      }
    } catch (e) {
      print('Error searching NZ addresses: $e');
      return _searchOpenStreetMapAddresses(query, 'New Zealand', limit);
    }
  }

  /// Search addresses using OpenStreetMap Nominatim API (free, fallback)
  static Future<List<AddressSearchResult>> _searchOpenStreetMapAddresses(String query, String country, int limit, {bool retry = true}) async {
    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'json',
          'limit': limit.toString(),
          'addressdetails': '1',
          if (country == 'New Zealand') 'countrycodes': 'nz',
        },
      );
      
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'SoleTradie Mobile App',
          'Referer': 'https://nominatim.openstreetmap.org/',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('OpenStreetMap API timeout');
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        return data
            .map((item) => AddressSearchResult.fromJson(item, 'OSM'))
            .where((result) => result.address.isNotEmpty)
            .toList();
      } else if (response.statusCode == 429 && retry) {
        print('⚠️ OpenStreetMap rate limit hit, retrying once after delay.');
        await Future.delayed(const Duration(seconds: 2));
        return _searchOpenStreetMapAddresses(query, country, limit, retry: false);
      } else if (response.statusCode == 403) {
        print('⚠️ OpenStreetMap API blocked (403). Ensure User-Agent is set correctly.');
        return [];
      } else {
        print('⚠️ OpenStreetMap API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('⚠️ Error searching addresses via OpenStreetMap: $e');
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
