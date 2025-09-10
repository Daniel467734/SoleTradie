import 'package:isar/isar.dart';

part 'sync_outbox.g.dart';

enum SyncAction { create, update, delete }

@collection
class SyncOutbox {
  Id? id;
  
  late String entityType; // 'PriceBookItem', 'SyncCustomer', etc.
  
  @Index()
  late String entityId; // Local entity ID
  late String? cloudId; // Cloud entity ID if it exists
  
  @Enumerated(EnumType.name)
  late SyncAction action;
  
  late String dataJson; // Serialized entity data
  
  @Index()
  late DateTime createdAt;
  late int retryCount;
  late DateTime? lastAttempt;
  late String? errorMessage;
  
  SyncOutbox({
    this.entityType = '',
    this.entityId = '',
    this.cloudId,
    this.action = SyncAction.create,
    this.dataJson = '',
    this.retryCount = 0,
    this.lastAttempt,
    this.errorMessage,
  }) {
    createdAt = DateTime.now();
  }
  
  // JSON serialization methods for mock implementation
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entityType': entityType,
      'entityId': entityId,
      'cloudId': cloudId,
      'action': action.name,
      'dataJson': dataJson,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'lastAttempt': lastAttempt?.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }
  
  factory SyncOutbox.fromJson(Map<String, dynamic> json) {
    final syncOutbox = SyncOutbox(
      entityType: json['entityType'] ?? '',
      entityId: json['entityId'] ?? '',
      cloudId: json['cloudId'],
      action: SyncAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => SyncAction.create,
      ),
      dataJson: json['dataJson'] ?? '',
      retryCount: json['retryCount'] ?? 0,
      lastAttempt: json['lastAttempt'] != null ? DateTime.parse(json['lastAttempt']) : null,
      errorMessage: json['errorMessage'],
    );
    syncOutbox.id = json['id'];
    if (json['createdAt'] != null) {
      syncOutbox.createdAt = DateTime.parse(json['createdAt']);
    }
    return syncOutbox;
  }
  
  // Convenience constructor for creating sync entries
  SyncOutbox.forSync({
    required String entityType,
    required String entityId,
    String? cloudId,
    required SyncAction action,
    required String data,
  }) : this(
    entityType: entityType,
    entityId: entityId,
    cloudId: cloudId,
    action: action,
    dataJson: data,
  );
}
