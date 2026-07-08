import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JobNumberService {
  static const String _lastJobSequenceKey = 'last_job_sequence';
  static const int _startingJobNumber = 2802;

  static Future<String> getNextJobId() async {
    final prefs = await SharedPreferences.getInstance();
    int sequence = prefs.getInt(_lastJobSequenceKey) ?? 0;

    if (sequence < _startingJobNumber - 1) {
      final existingSequence = await _findHighestExistingJobSequence();
      sequence = existingSequence > 0 ? existingSequence : _startingJobNumber - 1;
    }

    final next = sequence + 1;
    await prefs.setInt(_lastJobSequenceKey, next);
    return 'J$next';
  }

  static Future<int> _findHighestExistingJobSequence() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/jobs.json');
      if (!await file.exists()) return 0;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return 0;

      final parsed = jsonDecode(content);
      if (parsed is! List) return 0;

      int highest = 0;
      for (final item in parsed) {
        if (item is Map<String, dynamic>) {
          final id = item['id']?.toString();
          if (id != null && id.startsWith('J')) {
            final numeric = int.tryParse(id.substring(1));
            if (numeric != null && numeric > highest) {
              highest = numeric;
            }
          }
        }
      }

      return highest;
    } catch (e) {
      print('JobNumberService: failed to determine highest existing J job number: $e');
      return 0;
    }
  }

  static Future<String> peekNextJobId() async {
    final prefs = await SharedPreferences.getInstance();
    int sequence = prefs.getInt(_lastJobSequenceKey) ?? 0;

    if (sequence < _startingJobNumber - 1) {
      final existingSequence = await _findHighestExistingJobSequence();
      sequence = existingSequence > 0 ? existingSequence : _startingJobNumber - 1;
    }

    return 'J${sequence + 1}';
  }
}
