class TemplatePreference {
  final String templateName;
  final int starRating; // 1-5 stars
  final DateTime lastUsed;
  final int usageCount;

  TemplatePreference({
    required this.templateName,
    required this.starRating,
    required this.lastUsed,
    required this.usageCount,
  });

  Map<String, dynamic> toJson() => {
    'templateName': templateName,
    'starRating': starRating,
    'lastUsed': lastUsed.toIso8601String(),
    'usageCount': usageCount,
  };

  factory TemplatePreference.fromJson(Map<String, dynamic> json) => TemplatePreference(
    templateName: json['templateName'],
    starRating: json['starRating'],
    lastUsed: DateTime.parse(json['lastUsed']),
    usageCount: json['usageCount'],
  );

  TemplatePreference copyWith({
    String? templateName,
    int? starRating,
    DateTime? lastUsed,
    int? usageCount,
  }) => TemplatePreference(
    templateName: templateName ?? this.templateName,
    starRating: starRating ?? this.starRating,
    lastUsed: lastUsed ?? this.lastUsed,
    usageCount: usageCount ?? this.usageCount,
  );
}
