import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/recommendation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repository = LocalCatalogRepository();
  const engine = RecommendationEngine();

  test('female perfume respects recipient, budget and distinct alternative', () async {
    final products = await repository.loadProducts();
    final questions = await repository.loadQuestions();
    final result = engine.recommend(
      category: 'perfumeria',
      products: products,
      questions: questions,
      answers: const {
        'perf_destinatario': 'mujer',
        'perf_sensacion': 'dulce',
        'perf_momento': 'noche',
        'perf_intensidad': 'marcante',
        'perf_presupuesto': '175',
      },
    );

    expect(result.hasMatch, isTrue);
    expect(result.primary!.product.recipient, 'Mujer');
    expect(result.primary!.product.priceCop, lessThanOrEqualTo(175000));
    expect(result.alternative!.product.id, isNot(result.primary!.product.id));
  });

  test('hard budget can produce an honest no-match result', () async {
    final products = await repository.loadProducts();
    final questions = await repository.loadQuestions();
    final result = engine.recommend(
      category: 'cabello',
      products: products,
      questions: questions,
      answers: const {
        'cab_formato': 'shampoo',
        'cab_estado': 'seco',
        'cab_resultado': 'nutricion',
        'cab_frecuencia': 'lavado',
        'cab_presupuesto': '40',
      },
    );

    expect(result.hasMatch, isFalse);
  });

  test('ineligible product never enters facial ranking', () async {
    final products = await repository.loadProducts();
    final questions = await repository.loadQuestions();
    final result = engine.recommend(
      category: 'facial',
      products: products,
      questions: questions,
      answers: const {
        'fac_paso': 'solar',
        'fac_piel': 'normal',
        'fac_prioridad': 'luminosidad',
        'fac_momento': 'dia',
        'fac_presupuesto': '100',
      },
    );

    expect(result.primary?.product.id, isNot('OB046'));
    expect(result.alternative?.product.id, isNot('OB046'));
  });
}

