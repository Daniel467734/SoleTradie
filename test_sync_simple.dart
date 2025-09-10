// Simple test to verify SyncService import works
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'lib/services/sync_service.dart';

void main() {
  debugPrint('Testing SyncService import...');
  final connectivity = Connectivity();
  final service = SyncService(connectivity);
  debugPrint('Success: SyncService created: $service');
}
