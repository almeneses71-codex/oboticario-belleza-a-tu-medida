import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/cross_sell_engine.dart';
import '../domain/models/attribution_context.dart';
import '../domain/models/cross_sell_relation.dart';
import '../domain/models/cross_sell_result.dart';
import '../domain/models/customer_draft.dart';
import '../domain/models/order.dart';
import '../domain/models/order_selection.dart';
import '../domain/models/product.dart';
import '../domain/models/question.dart';
import '../domain/models/recommendation_result.dart';
import '../domain/recommendation_engine.dart';
import '../domain/repositories/catalog_repository.dart';
import '../domain/repositories/cross_sell_repository.dart';
import '../domain/repositories/order_repository.dart';
import '../services/analytics_service.dart';

enum AppStage { welcome, categories, questionnaire, processing, result }

class AppController extends ChangeNotifier {
  AppController({
    required CatalogRepository repository,
    required CrossSellRepository crossSellRepository,
    required OrderRepository? orderRepository,
    required AnalyticsService analytics,
    RecommendationEngine engine = const RecommendationEngine(),
    CrossSellEngine crossSellEngine = const CrossSellEngine(),
    AttributionContext? attribution,
  }) : _repository = repository,
       _crossSellRepository = crossSellRepository,
       _orderRepository = orderRepository,
       _analytics = analytics,
       _engine = engine,
       _crossSellEngine = crossSellEngine,
       attribution = attribution ?? AttributionContext.fromUri(Uri.base),
       journeyId = _newJourneyId();

  final CatalogRepository _repository;
  final CrossSellRepository _crossSellRepository;
  final OrderRepository? _orderRepository;
  final AnalyticsService _analytics;
  final RecommendationEngine _engine;
  final CrossSellEngine _crossSellEngine;
  final AttributionContext attribution;
  String journeyId;

  List<Product> products = const [];
  List<Product> _localProducts = const [];
  List<Question> questions = const [];
  List<CrossSellRelation> crossSellRelations = const [];
  AppStage stage = AppStage.welcome;
  String? selectedCategory;
  int questionIndex = 0;
  final Map<String, String> answers = {};
  RecommendationResult? result;
  bool loading = true;
  String? error;
  bool wheelCampaignActive = false;
  bool availabilityVerified = false;
  String? availabilityError;

  Future<void> initialize() async {
    try {
      _localProducts = await _repository.loadProducts();
      products = _localProducts;
      questions = await _repository.loadQuestions();
      crossSellRelations = await _crossSellRepository.loadRelations();
      final wheelRepository = _orderRepository;
      if (wheelRepository != null && wheelRepository is WheelRepository) {
        wheelCampaignActive =
            (await (wheelRepository as WheelRepository)
                    .loadWheelCampaignStatus())
                .active;
      }
      _validateData();
      await _syncAvailability();
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
    if (!await _syncAvailability()) return;
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
    journeyId = _newJourneyId();
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

  bool get orderSubmissionConfigured => _orderRepository?.isConfigured == true;

  Future<void> retryAvailability() async {
    loading = true;
    notifyListeners();
    await _syncAvailability();
    loading = false;
    notifyListeners();
  }

  Future<WheelBenefit> spinWheel({
    required CustomerDraft customer,
    required OrderSelection selection,
  }) async {
    if (!await _syncAvailability() || !_selectionIsPurchasable(selection)) {
      throw const OrderSubmissionUnavailable(
        'Estamos verificando la disponibilidad de nuestros productos.',
      );
    }
    final repository = _orderRepository;
    if (repository == null ||
        repository is! WheelRepository ||
        !wheelCampaignActive) {
      throw const OrderSubmissionUnavailable(
        'La campaña Amor y Amistad no está disponible.',
      );
    }
    return (repository as WheelRepository).spinWheel(
      customer: customer,
      items: selection.items,
    );
  }

  CrossSellResult crossSellFor(Product product) => _crossSellEngine.recommend(
    primary: product,
    products: products,
    relations: crossSellRelations,
  );

  Future<void> recordCrossSellShown(CrossSellCandidate candidate) =>
      _analytics.recordCrossSellShown(
        journeyId: journeyId,
        primaryProductId: candidate.relation.sourceProductId,
        complementaryProductId: candidate.product.id,
        relationId: candidate.relation.id,
        attribution: attribution,
      );

  Future<void> recordComplementaryChanged({
    required CrossSellCandidate candidate,
    required bool added,
  }) => _analytics.recordComplementaryChanged(
    journeyId: journeyId,
    added: added,
    primaryProductId: candidate.relation.sourceProductId,
    complementaryProductId: candidate.product.id,
    relationId: candidate.relation.id,
    attribution: attribution,
  );

  Future<CreatedOrder> createOrder({
    required CustomerDraft customer,
    required OrderSelection selection,
  }) async {
    final repository = _orderRepository;
    if (repository == null || !repository.isConfigured) {
      throw const OrderSubmissionUnavailable();
    }
    if (!await _syncAvailability() || !_selectionIsPurchasable(selection)) {
      throw const OrderSubmissionUnavailable(
        'Uno de los productos ya no está disponible. Actualiza tu selección.',
      );
    }
    return repository.createOrder(
      OrderDraft(
        journeyId: journeyId,
        customer: customer,
        attribution: attribution,
        items: selection.items,
        amounts: selection.amounts,
        shippingStatus: ShippingStatus.pendingQuote,
        requiresDelivery: true,
      ),
    );
  }

  bool _selectionIsPurchasable(OrderSelection selection) => selection.items
      .every((item) => products.any((product) => product.id == item.productId));

  Future<bool> _syncAvailability() async {
    final repository = _orderRepository;
    if (repository == null || repository is! ProductAvailabilityRepository) {
      products = const [];
      availabilityVerified = false;
      availabilityError =
          'Estamos verificando la disponibilidad de nuestros productos. '
          'Puedes intentar nuevamente o pedir asesoría.';
      notifyListeners();
      return false;
    }
    try {
      final ids = await (repository as ProductAvailabilityRepository)
          .loadPurchasableProductIds();
      products = _localProducts
          .where((product) => ids.contains(product.id))
          .toList(growable: false);
      availabilityVerified = true;
      availabilityError = null;
      notifyListeners();
      return true;
    } catch (_) {
      products = const [];
      availabilityVerified = false;
      availabilityError =
          'Estamos verificando la disponibilidad de nuestros productos. '
          'Puedes intentar nuevamente o pedir asesoría.';
      notifyListeners();
      return false;
    }
  }

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
      if (questions.where((item) => item.category == category).length != 4) {
        throw FormatException(
          '$category no contiene exactamente 4 preguntas específicas.',
        );
      }
    }
  }

  static String _newJourneyId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}
