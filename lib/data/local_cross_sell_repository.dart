import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/cross_sell_relation.dart';
import '../domain/repositories/cross_sell_repository.dart';

class LocalCrossSellRepository implements CrossSellRepository {
  const LocalCrossSellRepository();

  @override
  Future<List<CrossSellRelation>> loadRelations() async {
    final raw = await rootBundle.loadString(
      'assets/data/cross_sell_relations.json',
    );
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((item) => CrossSellRelation.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}
