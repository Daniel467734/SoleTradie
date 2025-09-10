import 'dart:convert';
import 'dart:io';

void main() {
  var file = File('test_timeline.json');
  var content = file.readAsStringSync();
  var data = json.decode(content);
  
  if (data.containsKey('semanticSegments')) {
    var segments = data['semanticSegments'] as List;
    print('Total segments: ${segments.length}');
    
    int visitCount = 0;
    int pathCount = 0;
    
    for (var segment in segments.take(10)) { // Check first 10 segments
      if (segment.containsKey('visit')) {
        visitCount++;
        print('Visit segment found: ${segment['visit']['topCandidate']?['placeLocation']?['latLng']}');
      }
      if (segment.containsKey('timelinePath')) {
        pathCount++;
        var path = segment['timelinePath'] as List;
        print('Path segment found with ${path.length} points');
      }
    }
    
    print('In first 10 segments: $visitCount visits, $pathCount paths');
  }
}
