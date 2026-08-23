import 'models/cross_sell_relation.dart';
import 'models/cross_sell_result.dart';
import 'models/product.dart';

class CrossSellEngine {
  const CrossSellEngine();

  CrossSellResult recommend({
    required Product primary,
    required Iterable<Product> products,
    required Iterable<CrossSellRelation> relations,
    DateTime? at,
  }) {
    final instant = at ?? DateTime.now();
    final productsById = {for (final product in products) product.id: product};
    final candidates = <CrossSellCandidate>[];

    for (final relation in relations) {
      if (relation.sourceProductId != primary.id ||
          !relation.isActiveAt(instant)) {
        continue;
      }
      final complementary = productsById[relation.complementaryProductId];
      if (complementary == null ||
          complementary.id == primary.id ||
          !complementary.available ||
          !complementary.eligible ||
          complementary.isSuggestedKit) {
        continue;
      }

      var score = relation.priority * 10;
      final reasons = <String>[relation.reason];
      if (primary.familyOrActive.trim().isNotEmpty &&
          primary.familyOrActive.toLowerCase() ==
              complementary.familyOrActive.toLowerCase()) {
        score += 5;
        reasons.add('Pertenece a una línea o familia compatible.');
      }
      if (primary.need.trim().isNotEmpty &&
          primary.need.toLowerCase() == complementary.need.toLowerCase()) {
        score += 5;
        reasons.add('Complementa la misma necesidad detectada.');
      }
      candidates.add(
        CrossSellCandidate(
          product: complementary,
          relation: relation,
          score: score,
          reasons: reasons.toSet().toList(growable: false),
        ),
      );
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byPrice = a.product.priceCop.compareTo(b.product.priceCop);
      if (byPrice != 0) return byPrice;
      return a.product.id.compareTo(b.product.id);
    });
    return CrossSellResult(candidates.take(2).toList(growable: false));
  }
}
