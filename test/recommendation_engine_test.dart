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

  test('moderate score still returns the closest facial products', () async {
    final result = await recommend('facial', const {
      'fac_necesidad': 'ojeras',
      'fac_piel': 'no_seguro',
      'fac_resultado': 'descansada',
      'fac_rutina': 'no_seguro',
    });
    expect(result.hasMatch, isTrue);
    expect(result.primary.score, inInclusiveRange(55, 69));
    expect(result.primary.product.category, 'facial');
    expect(result.alternative, isNotNull);
    expect(result.confidence, RecommendationConfidence.moderate);
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
    'hair and eligible September gifts both return stable results',
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
      expect(giftB.hasMatch, isTrue);
      expect(giftA.primary!.product.id, giftB.primary!.product.id);
    },
  );

  for (final scenario in const [
    ('hombre', 'Hombre'),
    ('mujer', 'Mujer'),
    ('no_seguro', 'Unisex'),
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
    final questions = await repository.loadQuestions();
    final routine = questions.firstWhere((item) => item.id == 'cab_rutina');
    final finish = routine.options.firstWhere(
      (item) => item.id == 'finalizacion',
    );
    expect(routine.text, '¿Qué paso quieres incorporar?');
    expect(finish.label, 'Producto para finalizar (leave-in)');
    expect(finish.boosts.single.queries, ['finalizador', 'leave-in']);

    final result = await recommend('cabello', {
      'cab_necesidad': 'nutricion',
      'cab_tipo': 'rubio',
      'cab_secundaria': 'crecimiento',
      'cab_rutina': finish.id,
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

  test('product without subtype loads with a neutral empty value', () {
    final json = _fixtureJson()..remove('subtype');
    expect(Product.fromJson(json).subtype, isEmpty);
  });

  test('product without role loads with a neutral empty value', () {
    final json = _fixtureJson()..remove('role');
    expect(Product.fromJson(json).role, isEmpty);
  });

  test('neutral role never receives the Principal tie-break advantage', () {
    final neutral = Product.fromJson(_fixtureJson(id: 'A', role: ''));
    final principal = Product.fromJson(
      _fixtureJson(id: 'Z', role: 'Principal'),
    );
    final result = engine.recommend(
      category: 'facial',
      products: [neutral, principal],
      questions: const [],
      answers: const {},
    );
    expect(result.primary!.product.id, 'Z');
  });

  test('unknown type earns no points from corp_tipo', () async {
    final unknown = Product.fromJson(
      _fixtureJson(id: 'A', category: 'corporal', type: ''),
    );
    final lotion = Product.fromJson(
      _fixtureJson(id: 'B', category: 'corporal', type: 'Loción corporal'),
    );
    final result = engine.recommend(
      category: 'corporal',
      products: [unknown, lotion],
      questions: await repository.loadQuestions(),
      answers: const {'corp_tipo': 'locion'},
    );
    expect(result.primary!.product.id, 'B');
    expect(result.primary!.score, 100);
    expect(result.alternative!.product.id, 'A');
    expect(result.alternative!.score, 0);
  });

  test(
    'unknown type still competes through other validated criteria',
    () async {
      final unknown = Product.fromJson(
        _fixtureJson(
          category: 'corporal',
          type: '',
          need: 'Hidratación diaria',
        ),
      );
      final result = engine.recommend(
        category: 'corporal',
        products: [unknown],
        questions: await repository.loadQuestions(),
        answers: const {'corp_necesidad': 'hidratar', 'corp_tipo': 'no_seguro'},
      );
      expect(result.primary!.product.id, unknown.id);
      expect(result.primary!.score, 100);
    },
  );

  for (final scenario in const [
    ('mujer', 'Mujer'),
    ('hombre', 'Hombre'),
    ('no_seguro', 'Unisex'),
  ]) {
    test('${scenario.$1} keeps the strict recipient boundary', () async {
      final products = ['Mujer', 'Hombre', 'Unisex']
          .map(
            (recipient) => Product.fromJson(
              _fixtureJson(
                id: recipient,
                category: 'perfumeria',
                recipient: recipient,
              ),
            ),
          )
          .toList();
      final result = engine.recommend(
        category: 'perfumeria',
        products: products,
        questions: await repository.loadQuestions(),
        answers: {'perf_destinatario': scenario.$1},
      );
      final returned = [result.primary, result.alternative]
          .whereType<RankedProduct>()
          .map((item) => item.product.recipient)
          .toSet();
      if (scenario.$2 == 'Unisex') {
        expect(returned, {'Unisex'});
      } else {
        expect(returned.difference({scenario.$2, 'Unisex'}), isEmpty);
      }
    });
  }

  test('ineligible and makeup products never enter a supported result', () {
    final ineligible = Product.fromJson(
      _fixtureJson(id: 'INELIGIBLE', eligible: false),
    );
    final makeup = Product.fromJson(
      _fixtureJson(id: 'MAKEUP', category: 'maquillaje'),
    );
    final result = engine.recommend(
      category: 'facial',
      products: [ineligible, makeup],
      questions: const [],
      answers: const {},
    );
    expect(result.hasMatch, isFalse);
  });

  test('primary and alternative always represent different products', () {
    final result = engine.recommend(
      category: 'facial',
      products: [
        Product.fromJson(_fixtureJson(id: 'A')),
        Product.fromJson(_fixtureJson(id: 'B')),
      ],
      questions: const [],
      answers: const {},
    );
    expect(result.primary!.product.id, isNot(result.alternative!.product.id));
  });

  test('existing liquid soap matches the corporal soap taxonomy', () async {
    final soap = Product.fromJson(
      _fixtureJson(category: 'corporal', type: 'Jabón líquido corporal'),
    );
    final result = engine.recommend(
      category: 'corporal',
      products: [soap],
      questions: await repository.loadQuestions(),
      answers: const {'corp_tipo': 'jabon'},
    );
    expect(result.primary!.score, 100);
  });
}

Map<String, dynamic> _fixtureJson({
  String id = 'FIXTURE',
  String category = 'facial',
  String type = 'Hidratante o tratamiento',
  String subtype = 'Hidratación',
  String recipient = 'Unisex',
  String role = 'Alternativa',
  String need = 'Hidratación',
  bool eligible = true,
}) => {
  'id': id,
  'category': category,
  'type': type,
  'subtype': subtype,
  'recipient': recipient,
  'name': 'Producto $id',
  'presentation': '1 unidad',
  'priceCop': 1,
  'familyOrActive': 'Familia',
  'intensity': 1,
  'need': need,
  'profile': 'Perfil',
  'moment': 'Momento',
  'available': true,
  'eligible': eligible,
  'code': id,
  'updated': '2026-09-05',
  'role': role,
  'isSuggestedKit': false,
};

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
