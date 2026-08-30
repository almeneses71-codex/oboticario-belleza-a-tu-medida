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
    final selections = <_Selection>[];

    for (final question in questions.where(
      (item) => item.category == category,
    )) {
      final answerId = answers[question.id];
      if (answerId == null) continue;

      selections.add(
        _Selection(
          question,
          question.options.firstWhere((option) => option.id == answerId),
        ),
      );
    }

    final applicable = selections
        .where((item) => !item.option.ignored && item.question.weight > 0)
        .toList(growable: false);

    final denominator = applicable.fold<int>(
      0,
      (sum, item) => sum + item.question.weight,
    );

    final recipientTarget = _resolveRecipientTarget(selections);

    final ranked = products
        .where((product) {
          if (product.category != category ||
              !product.available ||
              !product.eligible) {
            return false;
          }

          if (recipientTarget != null &&
              !_matchesRecipient(product.recipient, recipientTarget)) {
            return false;
          }

          return true;
        })
        .map((product) {
          var earned = 0.0;
          var primaryMatch = 0;
          var secondaryMatch = 0.0;
          final reasons = <String>[];

          for (final selection in applicable) {
            final quality = _matchQuality(product, selection.option);
            final weighted = selection.question.weight * quality / 100;

            earned += weighted;

            if (selection.question.primaryCriterion) {
              primaryMatch = quality;
            } else {
              secondaryMatch += weighted;
            }

            if (quality > 0 && selection.option.reason.isNotEmpty) {
              reasons.add(selection.option.reason);
            }
          }

          final score = denominator == 0
              ? 0
              : (earned * 100 / denominator).round();

          return _Candidate(
            ranked: RankedProduct(
              product: product,
              score: score,
              reasons: reasons.toSet().take(5).toList(growable: false),
            ),
            primaryMatch: primaryMatch,
            completeness: _completeness(product),
            secondaryMatch: secondaryMatch,
          );
        })
        .toList();

    if (ranked.isEmpty) {
      return _noMatch;
    }

    ranked.sort((a, b) {
      var order = b.ranked.score.compareTo(a.ranked.score);
      if (order != 0) return order;

      order = b.primaryMatch.compareTo(a.primaryMatch);
      if (order != 0) return order;

      order = b.completeness.compareTo(a.completeness);
      if (order != 0) return order;

      order = _roleRank(
        a.ranked.product,
      ).compareTo(_roleRank(b.ranked.product));
      if (order != 0) return order;

      order = b.secondaryMatch.compareTo(a.secondaryMatch);
      if (order != 0) return order;

      return a.ranked.product.id.compareTo(b.ranked.product.id);
    });

    final primary = ranked.first.ranked;

    return RecommendationResult(
      primary: primary,
      alternative: ranked.length > 1 ? ranked[1].ranked : null,
      confidence: primary.score >= 85
          ? RecommendationConfidence.high
          : primary.score >= 70
              ? RecommendationConfidence.good
              : primary.score >= 55
                  ? RecommendationConfidence.moderate
                  : RecommendationConfidence.low,
    );
  }

  static const _noMatch = RecommendationResult(
    primary: null,
    alternative: null,
    confidence: RecommendationConfidence.low,
  );

  String? _resolveRecipientTarget(List<_Selection> selections) {
    for (final selection in selections) {
      final questionId = selection.question.id.toLowerCase();

      if (!questionId.contains('destinatario')) {
        continue;
      }

      final optionId = selection.option.id.trim().toLowerCase();

      if (optionId == 'no_seguro') {
        return 'unisex';
      }

      final recipients =
          (selection.option.hardFilters['recipients'] as List<dynamic>?)
              ?.cast<String>();

      if (recipients != null && recipients.isNotEmpty) {
        return recipients.first.trim().toLowerCase();
      }

      if (optionId == 'hombre') {
        return 'hombre';
      }

      if (optionId == 'mujer') {
        return 'mujer';
      }
    }

    return null;
  }

  bool _matchesRecipient(String productRecipient, String target) {
    final normalized = productRecipient.trim().toLowerCase();

    if (target == 'unisex') {
      return normalized == 'unisex';
    }

    return normalized == target || normalized == 'unisex';
  }

  bool _passes(Product product, AnswerOption option) {
    final recipients =
        (option.hardFilters['recipients'] as List<dynamic>?)?.cast<String>();

    if (recipients != null && recipients.isNotEmpty) {
      final accepted = recipients
          .map((item) => item.trim().toLowerCase())
          .toSet();

      final productRecipient = product.recipient.trim().toLowerCase();

      if (!accepted.contains(productRecipient) &&
          productRecipient != 'unisex') {
        return false;
      }
    }

    final types =
        (option.hardFilters['types'] as List<dynamic>?)?.cast<String>();

    return types == null ||
        types.isEmpty ||
        types
            .map((item) => item.trim().toLowerCase())
            .contains(product.type.trim().toLowerCase());
  }

  int _matchQuality(Product product, AnswerOption option) {
    if (option.targetIntensity != null) {
      final difference = (product.intensity - option.targetIntensity!).abs();

      return difference == 0
          ? 100
          : difference == 1
              ? 70
              : difference == 2
                  ? 40
                  : 0;
    }

    var quality =
        option.hardFilters.isNotEmpty && _passes(product, option) ? 100 : 0;

    for (final boost in option.boosts) {
      if (boost.queries.any(
        (query) => product.searchableText.contains(query.toLowerCase()),
      )) {
        if (boost.points > quality) {
          quality = boost.points.clamp(0, 100);
        }
      }
    }

    return quality;
  }

  int _completeness(Product product) => [
        product.name,
        product.type,
        product.subtype,
        product.recipient,
        product.familyOrActive,
        product.need,
        product.profile,
        product.moment,
      ].where((value) => value.trim().isNotEmpty).length;

  int _roleRank(Product product) =>
      product.role.toLowerCase() == 'principal' ? 0 : 1;
}

class _Selection {
  const _Selection(this.question, this.option);

  final Question question;
  final AnswerOption option;
}

class _Candidate {
  const _Candidate({
    required this.ranked,
    required this.primaryMatch,
    required this.completeness,
    required this.secondaryMatch,
  });

  final RankedProduct ranked;
  final int primaryMatch;
  final int completeness;
  final double secondaryMatch;
}