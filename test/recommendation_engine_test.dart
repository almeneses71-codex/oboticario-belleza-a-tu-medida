import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/recommendation_engine.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/product.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/recommendation_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repository = LocalCatalogRepository();
  const engine = RecommendationEngine();

  Future<dynamic> recommend(
    String category,
    Map<String, String> answers,
  ) async {
    final purchasableProducts = (await repository.loadProducts())
        .where(
          (product) =>
              product.available && product.eligible && !product.isSuggestedKit,
        )
        .toList(growable: false);
    return engine.recommend(
      category: category,
      products: purchasableProducts,
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
    'hair stays stable while unofficial gifts remain advisory-only',
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
      expect(giftA.hasMatch, isFalse);
      expect(giftB.hasMatch, isFalse);
    },
  );

  for (final scenario in const [
    ('hombre', 'Hombre', 'KIT03'),
    ('mujer', 'Mujer', 'KIT01'),
    ('no_seguro', 'Unisex', 'KIT04'),
  ]) {
    test('gift fallback uses explicit ${scenario.$2} recipient', () async {
      final products = await repository.loadProducts();
      final verifiedKitFixtures = products
          .where((product) => product.category == 'regalos')
          .map(_asVerifiedKitFixture)
          .toList(growable: false);
      final result = engine.recommend(
        category: 'regalos',
        products: verifiedKitFixtures,
        questions: await repository.loadQuestions(),
        answers: {
          'reg_destinatario': scenario.$1,
          'reg_tipo': 'no_seguro',
          'reg_ocasion': 'no_seguro',
          'reg_nivel': 'no_seguro',
        },
      );
      expect(result.hasMatch, isTrue);
      expect(result.primary!.product.recipient, scenario.$2);
      expect(result.primary!.product.id, scenario.$3);
      expect(result.primary!.product.category, 'regalos');
    });
  }

  for (final category in const [
    'perfumeria',
    'cabello',
    'facial',
    'corporal',
  ]) {
    test(
      '$category falls back to a real product inside its category',
      () async {
        final result = await recommend(category, const {});
        expect(result.hasMatch, isTrue);
        expect(result.primary!.product.category, category);
        expect(result.primary!.product.available, isTrue);
        expect(result.primary!.product.eligible, isTrue);
        expect(result.primary!.product.isSuggestedKit, isFalse);
        expect(
          result.alternative == null ||
              result.alternative!.product.category == category,
          isTrue,
        );
      },
    );
  }

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

Product _asVerifiedKitFixture(Product product) => Product(
  id: product.id,
  category: product.category,
  type: product.type,
  subtype: product.subtype,
  recipient: product.recipient,
  name: product.name,
  presentation: product.presentation,
  priceCop: product.priceCop,
  familyOrActive: product.familyOrActive,
  intensity: product.intensity,
  need: product.need,
  profile: product.profile,
  moment: product.moment,
  available: true,
  eligible: true,
  code: product.code,
  updated: product.updated,
  role: product.role,
  isSuggestedKit: false,
  imagePath: product.imagePath,
);
