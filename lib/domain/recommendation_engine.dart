import 'models/product.dart';
import 'models/question.dart';
import 'models/recommendation_result.dart';

class RecommendationEngine {
  const RecommendationEngine();

  RecommendationResult recommend({
    required String category,
    required List<Product> products,
    required List<Question> questions,
    required Map<String, String> answers,
  }) {
    final selectedOptions = <AnswerOption>[];
    for (final question in questions.where((item) => item.category == category)) {
      final answerId = answers[question.id];
      if (answerId == null) continue;
      selectedOptions.add(
        question.options.firstWhere((option) => option.id == answerId),
      );
    }

    final eligible = products.where((product) {
      if (product.category != category ||
          !product.available ||
          !product.eligible) {
        return false;
      }
      return selectedOptions.every((option) => _passes(product, option));
    }).toList(growable: false);

    if (eligible.isEmpty) {
      return const RecommendationResult(
        primary: null,
        alternative: null,
        confidence: RecommendationConfidence.low,
      );
    }

    final ranked = eligible.map((product) {
      var score = product.role.toLowerCase() == 'principal' ? 1 : 0;
      final reasons = <String>['Responde a: ${product.need}.'];
      for (final option in selectedOptions) {
        var optionMatched = option.hardFilters.isNotEmpty;
        final target = option.targetIntensity;
        if (target != null) {
          score += (5 - (product.intensity - target).abs()).clamp(0, 5).toInt();
          optionMatched = true;
        }
        for (final boost in option.boosts) {
          if (boost.queries.any(
            (query) => product.searchableText.contains(query.toLowerCase()),
          )) {
            score += boost.points;
            optionMatched = true;
          }
        }
        if (optionMatched && option.reason.isNotEmpty) {
          reasons.add(option.reason);
        }
      }
      return RankedProduct(
        product: product,
        score: score,
        reasons: reasons.toSet().take(3).toList(growable: false),
      );
    }).toList();

    ranked.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      final roleOrder = _roleRank(a.product).compareTo(_roleRank(b.product));
      if (roleOrder != 0) return roleOrder;
      final priceOrder = a.product.priceCop.compareTo(b.product.priceCop);
      if (priceOrder != 0) return priceOrder;
      return a.product.id.compareTo(b.product.id);
    });

    final primary = ranked.first;
    final alternative = ranked.length > 1 ? ranked[1] : null;
    final gap = alternative == null ? primary.score : primary.score - alternative.score;
    final confidence = primary.score >= 12 && gap >= 2
        ? RecommendationConfidence.high
        : primary.score >= 6
            ? RecommendationConfidence.medium
            : RecommendationConfidence.low;
    return RecommendationResult(
      primary: primary,
      alternative: alternative,
      confidence: confidence,
    );
  }

  bool _passes(Product product, AnswerOption option) {
    final filters = option.hardFilters;
    final recipients = (filters['recipients'] as List<dynamic>?)?.cast<String>();
    if (recipients != null && recipients.isNotEmpty) {
      final recipient = product.recipient.toLowerCase();
      final accepted = recipients.map((item) => item.toLowerCase()).toSet();
      if (!accepted.contains(recipient) && recipient != 'unisex') return false;
    }
    final types = (filters['types'] as List<dynamic>?)?.cast<String>();
    if (types != null &&
        types.isNotEmpty &&
        !types.map((item) => item.toLowerCase()).contains(product.type.toLowerCase())) {
      return false;
    }
    final maxPrice = (filters['maxPrice'] as num?)?.toInt();
    if (maxPrice != null && product.priceCop > maxPrice) return false;
    return true;
  }

  int _roleRank(Product product) =>
      product.role.toLowerCase() == 'principal' ? 0 : 1;
}
