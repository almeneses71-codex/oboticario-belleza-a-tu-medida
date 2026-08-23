import '../models/cross_sell_relation.dart';

abstract interface class CrossSellRepository {
  Future<List<CrossSellRelation>> loadRelations();
}
