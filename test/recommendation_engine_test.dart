import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/recommendation_engine.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/recommendation_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repository = LocalCatalogRepository();
  const engine = RecommendationEngine();

  Future<dynamic> recommend(
    String category,
    Map<String, String> answers,
  ) async {
    return engine.recommend(
      category: category,
      products: await repository.loadProducts(),
      questions: await repository.loadQuestions(),
      answers: answers,
    );
  }

  test(
    'perfume uses recipient as hard filter and weighted preferences',
    () async {
      final result = await recommend('perfumeria', const {
        'perf_destinatario': 'mujer',
        'perf_aroma': 'dulce',
        'perf_ocasion': 'salida',
        'perf_intensidad': 'intensa',
      });
      expect(result.hasMatch, isTrue);
      expect(result.primary.product.recipient, 'Mujer');
      expect(result.primary.score, greaterThanOrEqualTo(85));
    },
  );

  test('unknown answers are excluded from the denominator', () async {
    final result = await recommend('corporal', const {
      'corp_destinatario': 'no_seguro',
      'corp_necesidad': 'hidratar',
      'corp_tipo': 'no_seguro',
      'corp_caracteristica': 'no_seguro',
    });
    expect(result.hasMatch, isTrue);
    expect(result.primary.score, 100);
  });

  test('score below 55 still returns the closest facial products', () async {
    final result = await recommend('facial', const {
      'fac_necesidad': 'ojeras',
      'fac_piel': 'no_seguro',
      'fac_resultado': 'descansada',
      'fac_rutina': 'no_seguro',
    });
    expect(result.hasMatch, isTrue);
    expect(result.primary.score, lessThan(55));
    expect(result.primary.product.category, 'facial');
    expect(result.alternative, isNotNull);
    expect(result.confidence, RecommendationConfidence.low);
  });

  test('ineligible product never enters facial ranking', () async {
    final result = await recommend('facial', const {
      'fac_necesidad': 'hidratacion',
      'fac_piel': 'grasa',
      'fac_resultado': 'hidratada',
      'fac_rutina': 'sencilla',
    });
    expect(result.primary?.product.id, isNot('OB046'));
    expect(result.alternative?.product.id, isNot('OB046'));
  });

  test(
    'hair and gifts produce catalog-backed stable recommendations',
    () async {
      final hair = await recommend('cabello', const {
        'cab_necesidad': 'dano',
        'cab_tipo': 'quimico',
        'cab_secundaria': 'reparacion',
        'cab_rutina': 'tratamiento',
      });
      final giftAnswers = const {
        'reg_destinatario': 'autocuidado',
        'reg_tipo': 'rutina',
        'reg_ocasion': 'autocuidado',
        'reg_nivel': 'especial',
      };
      final giftA = await recommend('regalos', giftAnswers);
      final giftB = await recommend('regalos', giftAnswers);
      expect(hair.hasMatch, isTrue);
      expect(giftA.hasMatch, isTrue);
      expect(giftA.primary.product.id, giftB.primary.product.id);
    },
  );

  test('real Xiaomi hair answers always stay inside hair category', () async {
    final result = await recommend('cabello', const {
      'cab_necesidad': 'nutricion',
      'cab_tipo': 'rubio',
      'cab_secundaria': 'crecimiento',
      'cab_rutina': 'finalizacion',
    });
    expect(result.hasMatch, isTrue);
    expect(result.primary.product.id, 'OB063');
    expect(result.primary.product.category, 'cabello');
    expect(result.alternative?.product.category, 'cabello');
  });

  test(
    'never falls back to another category when no valid candidate exists',
    () async {
      final products = await repository.loadProducts();
      final result = engine.recommend(
        category: 'facial',
        products: products.where((item) => item.category != 'facial').toList(),
        questions: await repository.loadQuestions(),
        answers: const {},
      );
      expect(result.hasMatch, isFalse);
    },
  );
}
