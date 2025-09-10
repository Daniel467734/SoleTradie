import 'dart:convert';
import 'dart:io';

double _calculateDuration(String startTime, String endTime) {
  try {
    DateTime start = DateTime.parse(startTime);
    DateTime end = DateTime.parse(endTime);
    return end.difference(start).inMinutes / 60.0;
  } catch (e) {
    return 0.0;
  }
}

void main() {
  var file = File('test_timeline.json');
  var content = file.readAsStringSync();
  var timelineData = json.decode(content);
  
  List<Map<String, dynamic>> gpsHistory = [];
  
  if (timelineData.containsKey('semanticSegments')) {
    List<dynamic> semanticSegments = timelineData['semanticSegments'];
    print('Processing ${semanticSegments.length} semantic segments');
    
    int processed = 0;
    for (var segment in semanticSegments.take(5)) { // Test first 5 segments
      if (segment.containsKey('visit')) {
        var visit = segment['visit'];
        
        if (visit.containsKey('topCandidate') && visit['topCandidate'].containsKey('placeLocation')) {
          var placeLocation = visit['topCandidate']['placeLocation'];
          if (placeLocation.containsKey('latLng')) {
            String latLngStr = placeLocation['latLng'];
            var coords = latLngStr.replaceAll('°', '').split(', ');
            if (coords.length == 2) {
              double lat = double.parse(coords[0]);
              double lng = double.parse(coords[1]);
              
              String? startTime = segment['startTime'];
              String? endTime = segment['endTime'];
              
              String? address;
              if (visit['topCandidate'].containsKey('placeId')) {
                address = 'Place ID: ${visit['topCandidate']['placeId']}';
              }
              if (visit['topCandidate'].containsKey('semanticType')) {
                String semanticType = visit['topCandidate']['semanticType'];
                address = semanticType != 'UNKNOWN' ? semanticType : address;
              }
              
              Map<String, dynamic> gpsEntry = {
                'latitude': lat,
                'longitude': lng,
                'timestamp': startTime ?? DateTime.now().toIso8601String(),
                'departureTime': endTime,
                'duration': endTime != null && startTime != null ? 
                  _calculateDuration(startTime, endTime) : null,
                'address': address ?? 'Location ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                'duration_start': startTime,
                'duration_end': endTime,
                'visit_confidence': 'HIGH',
                'probability': visit['probability']?.toString() ?? 'N/A',
              };
              
              gpsHistory.add(gpsEntry);
              processed++;
              print('✅ Added visit entry: ${gpsEntry['address']} at ${gpsEntry['timestamp']}');
            }
          }
        }
      }
    }
    
    print('\n📊 Successfully processed $processed entries');
    print('Total GPS entries created: ${gpsHistory.length}');
    
    if (gpsHistory.isNotEmpty) {
      print('\n📋 Sample entry:');
      var sample = gpsHistory.first;
      sample.forEach((key, value) {
        print('  $key: $value');
      });
    }
  }
}
