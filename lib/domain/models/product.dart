class Product {
  const Product({
    required this.id,
    required this.category,
    required this.type,
    required this.subtype,
    required this.recipient,
    required this.name,
    required this.presentation,
    required this.priceCop,
    required this.familyOrActive,
    required this.intensity,
    required this.need,
    required this.profile,
    required this.moment,
    required this.available,
    required this.eligible,
    required this.code,
    required this.updated,
    required this.role,
    required this.isSuggestedKit,
    this.imagePath = '',
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        category: json['category'] as String,
        type: json['type'] as String,
        subtype: json['subtype'] as String,
        recipient: json['recipient'] as String,
        name: json['name'] as String,
        presentation: json['presentation'] as String,
        priceCop: (json['priceCop'] as num).toInt(),
        familyOrActive: json['familyOrActive'] as String,
        intensity: (json['intensity'] as num).toInt(),
        need: json['need'] as String,
        profile: json['profile'] as String,
        moment: json['moment'] as String,
        available: json['available'] as bool,
        eligible: json['eligible'] as bool,
        code: json['code'] as String,
        updated: json['updated'] as String,
        role: json['role'] as String,
        isSuggestedKit: json['isSuggestedKit'] as bool? ?? false,
        imagePath: json['imagePath'] as String? ?? '',
      );

  final String id;
  final String category;
  final String type;
  final String subtype;
  final String recipient;
  final String name;
  final String presentation;
  final int priceCop;
  final String familyOrActive;
  final int intensity;
  final String need;
  final String profile;
  final String moment;
  final bool available;
  final bool eligible;
  final String code;
  final String updated;
  final String role;
  final bool isSuggestedKit;
  final String imagePath;

  /// Uses a custom path from products.json when present. Otherwise each
  /// product automatically resolves its image from its stable product ID.
  String get resolvedImagePath =>
      imagePath.isNotEmpty ? imagePath : 'assets/images/products/$id.webp';

  String get searchableText => [
        type,
        subtype,
        recipient,
        name,
        familyOrActive,
        need,
        profile,
        moment,
      ].join(' ').toLowerCase();
}
