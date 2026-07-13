class SyncCustomer {
  int? id;

  late String customerId; // External customer ID
  
  late String name;
  late String? email;
  late String? phone;
  late String? address;
  late String? notes;
  
  late DateTime createdAt;
  late DateTime updatedAt;
  
  // Remote customer flag - when true, all customer data is cached locally
  late bool isRemote;
  
  // Sync fields
  late bool isDeleted;
  late bool needsSync;
  late String? cloudId;
  
  SyncCustomer({
    this.customerId = '',
    this.name = '',
    this.email,
    this.phone,
    this.address,
    this.notes,
    this.isRemote = false,
    this.isDeleted = false,
    this.needsSync = true,
    this.cloudId,
  }) {
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
  
  Map<String, dynamic> toFirestore() {
    return {
      'customerId': customerId,
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'notes': notes,
      'isRemote': isRemote,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }
  
  // Add toJson for serialization
  Map<String, dynamic> toJson() => toFirestore();
  
  // Add fromJson for deserialization
  factory SyncCustomer.fromJson(Map<String, dynamic> json) {
    return SyncCustomer(
      customerId: json['customerId'] ?? '',
      name: json['name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      address: json['address'],
      notes: json['notes'],
      isRemote: json['isRemote'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      needsSync: json['needsSync'] ?? true,
      cloudId: json['cloudId'],
    )
      ..id = json['id']
      ..createdAt = json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now()
      ..updatedAt = json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now();
  }
  
  factory SyncCustomer.fromFirestore(Map<String, dynamic> data, String docId) {
    return SyncCustomer(
      customerId: data['customerId'] ?? '',
      name: data['name'] ?? '',
      email: data['email'],
      phone: data['phone'],
      address: data['address'],
      notes: data['notes'],
      isRemote: data['isRemote'] ?? false,
      isDeleted: data['isDeleted'] ?? false,
      needsSync: false,
      cloudId: docId,
    )
      ..createdAt = data['createdAt'] != null ? DateTime.parse(data['createdAt']) : DateTime.now()
      ..updatedAt = data['updatedAt'] != null ? DateTime.parse(data['updatedAt']) : DateTime.now();
  }
}
