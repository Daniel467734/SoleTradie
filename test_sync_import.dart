import 'lib/services/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

void main() {
  final connectivity = Connectivity();
  final service = SyncService(connectivity);
  debugPrint('SyncService imported successfully: $service');
}
