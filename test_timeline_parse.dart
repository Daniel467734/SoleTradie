import 'dart:convert';
import 'dart:io';

void main() {
  var file = File('test_timeline.json');
  if (!file.existsSync()) {
    print('Timeline file not found');
    return;
  }
  
  var content = file.readAsStringSync();
  var data = json.decode(content);
  
  print('Top-level keys: ${data.keys.toList()}');
  
  if (data.containsKey('semanticSegments')) {
    var segments = data['semanticSegments'] as List;
    print('Found ${segments.length} semantic segments');
    
    if (segments.isNotEmpty) {
      var firstSegment = segments.first;
      print('First segment keys: ${firstSegment.keys.toList()}');
      
      if (firstSegment.containsKey('visit')) {
        print('Found visit data in first segment');
        var visit = firstSegment['visit'];
        if (visit.containsKey('topCandidate')) {
          print('Found topCandidate in visit');
          var topCandidate = visit['topCandidate'];
          if (topCandidate.containsKey('placeLocation')) {
            print('Found placeLocation in topCandidate');
            var placeLocation = topCandidate['placeLocation'];
            if (placeLocation.containsKey('latLng')) {
              var latLng = placeLocation['latLng'];
              print('Found coordinates: $latLng');
            }
          }
        }
      }
      
      if (firstSegment.containsKey('timelinePath')) {
        print('Found timelinePath in first segment');
        var timelinePath = firstSegment['timelinePath'];
        if (timelinePath is List && timelinePath.isNotEmpty) {
          print('First timeline path point: ${timelinePath.first}');
        }
      }
    }
  } else {
    print('No semanticSegments found');
  }
}
