import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/product.dart';
import '../domain/models/question.dart';
import '../domain/repositories/catalog_repository.dart';

class LocalCatalogRepository implements CatalogRepository {
  const LocalCatalogRepository();

  @override
  Future<List<Product>> loadProducts() async {
    final raw = await rootBundle.loadString('assets/data/products.json');
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<Question>> loadQuestions() async {
    final raw = await rootBundle.loadString('assets/data/questionnaire.json');
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((item) => Question.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}

