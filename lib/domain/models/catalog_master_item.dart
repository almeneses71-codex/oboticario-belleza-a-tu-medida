class CatalogMasterItem {
  const CatalogMasterItem({
    required this.code,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.description,
    required this.characteristics,
    required this.priceCop,
    required this.presentation,
    required this.available,
    required this.officialUrl,
  });

  factory CatalogMasterItem.fromJson(Map<String, dynamic> json) =>
      CatalogMasterItem(
        code: json['code'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        subcategory: json['subcategory'] as String,
        description: json['description'] as String,
        characteristics: (json['characteristics'] as List<dynamic>)
            .cast<String>(),
        priceCop: (json['priceCop'] as num).toInt(),
        presentation: json['presentation'] as String,
        available: json['available'] as bool,
        officialUrl: json['officialUrl'] as String,
      );

  final String code;
  final String name;
  final String category;
  final String subcategory;
  final String description;
  final List<String> characteristics;
  final int priceCop;
  final String presentation;
  final bool available;
  final String officialUrl;

  bool get isKit => subcategory.toLowerCase() == 'kit';
  bool get canRequest => available && !isKit;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return [
      code,
      name,
      category,
      subcategory,
      description,
    ].join(' ').toLowerCase().contains(normalized);
  }
}
