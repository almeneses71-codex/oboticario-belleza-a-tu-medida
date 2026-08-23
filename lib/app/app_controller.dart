import 'package:flutter/foundation.dart';

import '../domain/models/product.dart';
import '../domain/models/question.dart';
import '../domain/models/recommendation_result.dart';
import '../domain/recommendation_engine.dart';
import '../domain/repositories/catalog_repository.dart';
import '../services/analytics_service.dart';

enum AppStage { welcome, categories, questionnaire, processing, result }

class AppController extends ChangeNotifier {
  AppController({
    required CatalogRepository repository,
    required AnalyticsService analytics,
    RecommendationEngine engine = const RecommendationEngine(),
  }) : _repository = repository,
       _analytics = analytics,
       _engine = engine;

  final CatalogRepository _repository;
  final AnalyticsService _analytics;
  final RecommendationEngine _engine;

  List<Product> products = const [];
  List<Question> questions = const [];
  AppStage stage = AppStage.welcome;
  String? selectedCategory;
  int questionIndex = 0;
  final Map<String, String> answers = {};
  RecommendationResult? result;
  bool loading = true;
  String? error;

  Future<void> initialize() async {
    try {
      products = await _repository.loadProducts();
      questions = await _repository.loadQuestions();
      _validateData();
      await _analytics.recordAppOpen();
    } catch (exception) {
      error = 'No fue posible cargar el catálogo: $exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<Question> get categoryQuestions =>
      questions
          .where((question) => question.category == selectedCategory)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  Question? get currentQuestion {
    final items = categoryQuestions;
    return items.isEmpty ? null : items[questionIndex];
  }

  void begin() {
    stage = AppStage.categories;
    notifyListeners();
  }

  void selectCategory(String category) {
    selectedCategory = category;
    questionIndex = 0;
    answers.clear();
    result = null;
    stage = AppStage.questionnaire;
    notifyListeners();
  }

  void selectAnswer(AnswerOption option) {
    final question = currentQuestion;
    if (question == null) return;
    answers[question.id] = option.id;
    notifyListeners();
  }

  Future<void> continueQuestion() async {
    final question = currentQuestion;
    if (question == null || answers[question.id] == null) return;
    if (questionIndex < categoryQuestions.length - 1) {
      questionIndex++;
      notifyListeners();
      return;
    }
    stage = AppStage.processing;
    notifyListeners();
    // Yield once so the processing state can render without adding a delay.
    await Future<void>.delayed(Duration.zero);
    result = _engine.recommend(
      category: selectedCategory!,
      products: products,
      questions: questions,
      answers: answers,
    );
    stage = AppStage.result;
    notifyListeners();
    await _analytics.recordQuizCompleted(
      selectedCategory!,
      result?.primary?.product.id,
    );
  }

  Future<void> answer(AnswerOption option) async {
    selectAnswer(option);
    await continueQuestion();
  }

  void back() {
    if (stage == AppStage.questionnaire && questionIndex > 0) {
      questionIndex--;
    } else if (stage == AppStage.questionnaire) {
      stage = AppStage.categories;
    } else if (stage == AppStage.categories) {
      stage = AppStage.welcome;
    }
    notifyListeners();
  }

  void restart() {
    selectedCategory = null;
    questionIndex = 0;
    answers.clear();
    result = null;
    stage = AppStage.categories;
    notifyListeners();
  }

  List<String> get selectedAnswerLabels {
    final labels = <String>[];
    for (final question in categoryQuestions) {
      final answerId = answers[question.id];
      if (answerId == null) continue;
      labels.add(
        question.options.firstWhere((item) => item.id == answerId).label,
      );
    }
    return labels;
  }

  Future<void> recordWhatsappClick(String? productId) =>
      _analytics.recordWhatsappClick(productId);

  void _validateData() {
    final ids = products.map((item) => item.id).toList();
    if (ids.toSet().length != ids.length) {
      throw const FormatException(
        'Hay identificadores de producto duplicados.',
      );
    }
    if (products.any((item) => item.priceCop < 0)) {
      throw const FormatException('Hay precios negativos.');
    }
    const categories = {
      'perfumeria',
      'corporal',
      'facial',
      'cabello',
      'regalos',
    };
    if (products.any((item) => !categories.contains(item.category)) ||
        questions.any((item) => !categories.contains(item.category))) {
      throw const FormatException('Hay categorías desconocidas.');
    }
    for (final category in categories) {
      if (questions.where((item) => item.category == category).length != 5) {
        throw FormatException('$category no contiene exactamente 5 preguntas.');
      }
    }
  }
}
