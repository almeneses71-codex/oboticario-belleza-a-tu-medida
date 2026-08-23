import 'product.dart';

enum RecommendationConfidence { high, good, moderate, low }

class RankedProduct {
  const RankedProduct({
    required this.product,
    required this.score,
    required this.reasons,
  });

  final Product product;
  final int score;
  final List<String> reasons;
}

class RecommendationResult {
  const RecommendationResult({
    required this.primary,
    required this.alternative,
    required this.confidence,
  });

  final RankedProduct? primary;
  final RankedProduct? alternative;
  final RecommendationConfidence confidence;

  bool get hasMatch => primary != null;
}
