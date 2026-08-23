import 'cross_sell_relation.dart';
import 'product.dart';

class CrossSellCandidate {
  const CrossSellCandidate({
    required this.product,
    required this.relation,
    required this.score,
    required this.reasons,
  });

  final Product product;
  final CrossSellRelation relation;
  final int score;
  final List<String> reasons;
}

class CrossSellResult {
  const CrossSellResult(this.candidates);

  final List<CrossSellCandidate> candidates;
}
