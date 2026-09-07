import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/recommendation_result.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/recommendation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repository = LocalCatalogRepository();
  const engine = RecommendationEngine();

  test('representative September recommendation matrix stays strict', () async {
    final products = await repository.loadProducts();
    final questions = await repository.loadQuestions();
    const scenarios = [
      (
        'perfumeria-mujer',
        'perfumeria',
        'Mujer',
        {
          'perf_destinatario': 'mujer',
          'perf_aroma': 'dulce',
          'perf_ocasion': 'salida',
          'perf_intensidad': 'intensa',
        },
      ),
      (
        'perfumeria-hombre',
        'perfumeria',
        'Hombre',
        {
          'perf_destinatario': 'hombre',
          'perf_aroma': 'fresca',
          'perf_ocasion': 'diario',
          'perf_intensidad': 'equilibrada',
        },
      ),
      (
        'perfumeria-no-seguro',
        'perfumeria',
        'Unisex',
        {
          'perf_destinatario': 'no_seguro',
          'perf_aroma': 'floral',
          'perf_ocasion': 'versatil',
          'perf_intensidad': 'suave',
        },
      ),
      (
        'corporal-mujer',
        'corporal',
        'Mujer',
        {
          'corp_destinatario': 'mujer',
          'corp_necesidad': 'hidratar',
          'corp_tipo': 'locion',
          'corp_caracteristica': 'duracion',
        },
      ),
      (
        'corporal-hombre',
        'corporal',
        'Hombre',
        {
          'corp_destinatario': 'hombre',
          'corp_necesidad': 'perfumar',
          'corp_tipo': 'splash',
          'corp_caracteristica': 'aroma',
        },
      ),
      (
        'corporal-no-seguro',
        'corporal',
        'Unisex',
        {
          'corp_destinatario': 'no_seguro',
          'corp_necesidad': 'limpiar',
          'corp_tipo': 'jabon',
          'corp_caracteristica': 'suavidad',
        },
      ),
      (
        'facial',
        'facial',
        null,
        {
          'fac_necesidad': 'hidratacion',
          'fac_piel': 'sensible',
          'fac_resultado': 'hidratada',
          'fac_rutina': 'sencilla',
        },
      ),
      (
        'cabello',
        'cabello',
        null,
        {
          'cab_necesidad': 'dano',
          'cab_tipo': 'quimico',
          'cab_secundaria': 'reparacion',
          'cab_rutina': 'tratamiento',
        },
      ),
      (
        'regalos-mujer',
        'regalos',
        'Mujer',
        {
          'reg_destinatario': 'mujer',
          'reg_tipo': 'perfume',
          'reg_ocasion': 'especial',
          'reg_nivel': 'especial',
        },
      ),
      (
        'regalos-hombre',
        'regalos',
        'Hombre',
        {
          'reg_destinatario': 'hombre',
          'reg_tipo': 'perfume',
          'reg_ocasion': 'especial',
          'reg_nivel': 'especial',
        },
      ),
      (
        'regalos-no-seguro',
        'regalos',
        'Unisex',
        {
          'reg_destinatario': 'no_seguro',
          'reg_tipo': 'corporal',
          'reg_ocasion': 'autocuidado',
          'reg_nivel': 'sencillo',
        },
      ),
    ];

    for (final scenario in scenarios) {
      final result = engine.recommend(
        category: scenario.$2,
        products: products,
        questions: questions,
        answers: scenario.$4,
      );
      final returned = [
        result.primary,
        result.alternative,
      ].whereType<RankedProduct>().toList(growable: false);

      for (final item in returned) {
        expect(item.product.category, scenario.$2);
        expect(item.product.eligible, isTrue);
        expect(item.product.available, isTrue);
        expect(item.product.category, isNot('maquillaje'));
        if (scenario.$3 == 'Unisex') {
          expect(item.product.recipient, 'Unisex');
        } else if (scenario.$3 != null) {
          expect(item.product.recipient, anyOf(scenario.$3, 'Unisex'));
        }
      }
      if (returned.length == 2) {
        expect(returned[0].product.id, isNot(returned[1].product.id));
      }

      debugPrint(
        'MATRIX ${jsonEncode({'case': scenario.$1, 'category': scenario.$2, 'targetRecipient': scenario.$3, 'primary': _resultJson(result.primary), 'alternative': _resultJson(result.alternative)})}',
      );
    }
  });
}

Map<String, dynamic>? _resultJson(RankedProduct? ranked) {
  if (ranked == null) return null;
  final product = ranked.product;
  return {
    'name': product.name,
    'code': product.code,
    'category': product.category,
    'recipient': product.recipient,
    'eligible': product.eligible,
    'available': product.available,
    'score': ranked.score,
    'typeKnown': product.type.isNotEmpty,
  };
}
