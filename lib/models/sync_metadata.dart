/// Tracks sync metadata for efficient delta syncing
/// Instead of fetching all data every time, we track what's changed
/// and only fetch the differences from the cloud
class SyncMetadata {
  /// Last timestamp we successfully synced this collection
  final DateTime lastSyncTime;

  /// Hash of all data as it was at last sync (to detect changes)
  final String? dataHash;

  /// Cloud version number for the entire collection
  final int? cloudVersion;

  /// For each entity, track its last known update time
  final Map<String, DateTime> entityTimestamps;

  SyncMetadata({
    required this.lastSyncTime,
    this.dataHash,
    this.cloudVersion,
    this.entityTimestamps = const {},
  });

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    return SyncMetadata(
      lastSyncTime: DateTime.parse(json['lastSyncTime'] as String),
      dataHash: json['dataHash'],
      cloudVersion: json['cloudVersion'],
      entityTimestamps: (json['entityTimestamps'] as Map<String, dynamic>? ?? {})
          .cast<String, String>()
          .map((k, v) => MapEntry(k, DateTime.parse(v))),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastSyncTime': lastSyncTime.toIso8601String(),
      'dataHash': dataHash,
      'cloudVersion': cloudVersion,
      'entityTimestamps': entityTimestamps
          .map((k, v) => MapEntry(k, v.toIso8601String())),
    };
  }

  /// Create initial empty sync metadata
  static SyncMetadata initial() {
    return SyncMetadata(
      lastSyncTime: DateTime.now(),
      dataHash: null,
      cloudVersion: null,
      entityTimestamps: {},
    );
  }
}
