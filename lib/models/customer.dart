class Customer {
  final String id;
  final String name;
  final String lastName;
  final String companyName;
  final String address;
  final String email;
  final List<String> additionalEmails;
  final String phone;
  final String paymentTerms;
  final String bodyCorporateNumber;
  final bool isRemote; // Remote customer flag - when true, all customer data uses hybrid storage

  Customer({
    required this.id,
    required this.name,
    this.lastName = '',
    this.companyName = '',
    required this.address,
    required this.email,
    this.additionalEmails = const [],
    required this.phone,
    this.paymentTerms = '7 days',
    this.bodyCorporateNumber = '',
    this.isRemote = false,
  });

  Customer copyWith({
    String? id,
    String? name,
    String? lastName,
    String? companyName,
    String? address,
    String? email,
    List<String>? additionalEmails,
    String? phone,
    String? paymentTerms,
    String? bodyCorporateNumber,
    bool? isRemote,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      lastName: lastName ?? this.lastName,
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      email: email ?? this.email,
      additionalEmails: additionalEmails ?? this.additionalEmails,
      phone: phone ?? this.phone,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      bodyCorporateNumber: bodyCorporateNumber ?? this.bodyCorporateNumber,
      isRemote: isRemote ?? this.isRemote,
    );
  }

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        lastName: (json['lastName'] ?? '').toString(),
        companyName: (json['companyName'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        additionalEmails: List<String>.from(
          (json['additionalEmails'] as List<dynamic>? ?? const [])
              .map((e) => (e ?? '').toString()),
        ),
        phone: (json['phone'] ?? '').toString(),
        paymentTerms: (json['paymentTerms'] ?? '7 days').toString(),
        bodyCorporateNumber: (json['bodyCorporateNumber'] ?? '').toString(),
        isRemote: json['isRemote'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastName': lastName,
        'companyName': companyName,
        'address': address,
        'email': email,
        'additionalEmails': additionalEmails,
        'phone': phone,
        'paymentTerms': paymentTerms,
        'bodyCorporateNumber': bodyCorporateNumber,
        'isRemote': isRemote,
      };

  /// Full name combining first name (`name`) and `lastName`, trimmed.
  String get fullName => [name, lastName].where((s) => s.trim().isNotEmpty).join(' ');

  /// Returns all email addresses for this customer (primary + additional)
  List<String> getAllEmails() {
    final emails = <String>[];
    if (email.trim().isNotEmpty) {
      emails.add(email);
    }
    emails.addAll(additionalEmails.where((e) => e.trim().isNotEmpty));
    return emails;
  }

  /// Returns the display name (name or company name)
  String get displayName {
    if (name.trim().isNotEmpty) {
      return name;
    }
    return companyName.trim().isNotEmpty ? companyName : 'Unnamed Customer';
  }
}
