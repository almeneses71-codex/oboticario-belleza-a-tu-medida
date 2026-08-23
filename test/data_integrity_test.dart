import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog contains 64 individual products and 4 suggested kits', () async {
    final raw = await rootBundle.loadString('assets/data/products.json');
    final products = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final ids = products.map((item) => item['id'] as String).toList();

    expect(products, hasLength(68));
    expect(ids.toSet(), hasLength(68));
    expect(products.where((item) => item['isSuggestedKit'] == true), hasLength(4));
    expect(products.where((item) => item['eligible'] == false), hasLength(1));
    expect(products.every((item) => (item['priceCop'] as num) >= 0), isTrue);
  });

  test('each category contains exactly five questions', () async {
    final raw = await rootBundle.loadString('assets/data/questionnaire.json');
    final questions = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    const categories = {'perfumeria', 'corporal', 'facial', 'cabello', 'regalos'};

    expect(questions, hasLength(25));
    for (final category in categories) {
      expect(
        questions.where((item) => item['category'] == category),
        hasLength(5),
      );
    }
    expect(
      questions.every((item) => (item['options'] as List<dynamic>).isNotEmpty),
      isTrue,
    );
  });
}

