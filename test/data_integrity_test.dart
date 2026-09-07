import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog contains the 252 eligible September products', () async {
    final raw = await rootBundle.loadString('assets/data/products.json');
    final products = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final ids = products.map((item) => item['id'] as String).toList();

    final codes = products.map((item) => item['code'] as String).toList();
    const categories = {
      'perfumeria',
      'corporal',
      'facial',
      'cabello',
      'regalos',
    };
    const recipients = {'Mujer', 'Hombre', 'Unisex'};
    const criticalFields = {
      'id',
      'category',
      'recipient',
      'name',
      'presentation',
      'priceCop',
      'familyOrActive',
      'intensity',
      'need',
      'profile',
      'moment',
      'code',
      'updated',
    };

    expect(products, hasLength(252));
    expect(ids.toSet(), hasLength(252));
    expect(codes.toSet(), hasLength(252));
    expect(products.every((item) => item['eligible'] == true), isTrue);
    expect(products.every((item) => item['available'] == true), isTrue);
    expect(products.every((item) => item['isSuggestedKit'] == false), isTrue);
    expect(
      products.every((item) => categories.contains(item['category'])),
      isTrue,
    );
    expect(
      products.every((item) => recipients.contains(item['recipient'])),
      isTrue,
    );
    expect(
      products.every(
        (item) => criticalFields.every((field) {
          final value = item[field];
          return value != null && (value is! String || value.isNotEmpty);
        }),
      ),
      isTrue,
    );
    expect(products.every((item) => (item['priceCop'] as num) > 0), isTrue);
    expect(products.where((item) => item['category'] == 'maquillaje'), isEmpty);
  });

  test(
    'each category contains four questions after category selection',
    () async {
      final raw = await rootBundle.loadString('assets/data/questionnaire.json');
      final questions = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      const categories = {
        'perfumeria',
        'corporal',
        'facial',
        'cabello',
        'regalos',
      };

      expect(questions, hasLength(20));
      for (final category in categories) {
        expect(
          questions.where((item) => item['category'] == category),
          hasLength(4),
        );
      }
      expect(
        questions.every(
          (item) => (item['options'] as List<dynamic>).isNotEmpty,
        ),
        isTrue,
      );
      expect(questions.every((item) => item.containsKey('weight')), isTrue);
    },
  );
}
