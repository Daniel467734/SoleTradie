import 'lib/services/address_search_service.dart';

void main() async {
  print('Testing Address API improvements...');
  
  // Test address search
  print('\n--- Testing address search with numbers ---');
  final results = await AddressSearchService.searchAddresses('123 Queen Street, Auckland');
  
  for (int i = 0; i < results.length && i < 5; i++) {
    final result = results[i];
    print('Address $i: ${result.address}');
    if (result.distanceKm != null) {
      print('  Distance: ${result.distanceKm!.toStringAsFixed(1)} km');
    }
    print('  Coords: ${result.latitude}, ${result.longitude}');
    print('  City: ${result.city}');
    print('');
  }
  
  // Test company coordinates
  print('\n--- Testing company coordinates ---');
  final companyCoords = await AddressSearchService.getCompanyCoordinates();
  if (companyCoords != null) {
    print('Company coordinates: ${companyCoords['latitude']}, ${companyCoords['longitude']}');
  } else {
    print('No company coordinates available');
  }
  
  print('\nAddress API test completed!');
}
