import '../colombian_mobile_number.dart';

class CustomerDraft {
  const CustomerDraft({
    required this.name,
    required this.whatsapp,
    required this.acceptsDataProcessing,
    required this.acceptsPromotions,
    this.city,
  });

  final String name;
  final String whatsapp;
  final String? city;
  final bool acceptsDataProcessing;
  final bool acceptsPromotions;

  bool get isValid =>
      name.trim().length >= 2 &&
      ColombianMobileNumber.isValid(whatsapp) &&
      acceptsDataProcessing;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'whatsapp': ColombianMobileNumber.normalize(whatsapp),
    'city': city?.trim(),
    'acceptsDataProcessing': acceptsDataProcessing,
    'acceptsPromotions': acceptsPromotions,
  };
}
