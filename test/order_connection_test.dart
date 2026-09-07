import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app_controller.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/attribution_context.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/customer_draft.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order_selection.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/product.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/order_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/recommendation_engine.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local mode keeps recommendations available without Supabase', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(
      repository: const LocalCatalogRepository(),
      crossSellRepository: const LocalCrossSellRepository(),
      orderRepository: null,
      analytics: LocalAnalyticsService(),
    );

    await controller.initialize();

    expect(controller.availabilityVerified, isTrue);
    expect(controller.availabilityError, isNull);
    expect(controller.products, isNotEmpty);
    expect(
      controller.products.every(
        (product) =>
            product.available && product.eligible && !product.isSuggestedKit,
      ),
      isTrue,
    );
    expect(controller.orderSubmissionConfigured, isFalse);
  });

  test(
    'availability intersection exposes all 252 eligible Cloud IDs',
    () async {
      final controller = await _controller(_FakeOrderRepository());
      final localIds = (await const LocalCatalogRepository().loadProducts())
          .map((product) => product.id)
          .toSet();

      expect(controller.products, hasLength(252));
      expect(
        controller.products.map((product) => product.id).toSet(),
        localIds,
      );
    },
  );

  test('hair finish label keeps the finalizacion answer ID', () async {
    final controller = await _controller(_FakeOrderRepository());
    controller.selectCategory('cabello');
    while (controller.currentQuestion!.id != 'cab_rutina') {
      final option = controller.currentQuestionOptions.firstWhere(
        (item) => item.id == 'no_seguro',
      );
      controller.selectAnswer(option);
      await controller.continueQuestion();
    }
    final finish = controller.currentQuestionOptions.firstWhere(
      (item) => item.id == 'finalizacion',
    );

    expect(finish.label, 'Producto para finalizar (leave-in)');
    controller.selectAnswer(finish);
    expect(controller.answers['cab_rutina'], 'finalizacion');
  });

  test(
    'selected alternative and attribution reach the order repository',
    () async {
      final fake = _FakeOrderRepository();
      final controller = await _controller(fake);
      final alternative = controller.products.firstWhere(
        (item) => item.id == 'OB002',
      );
      final selection = OrderSelection.fromPrimary(alternative);

      final created = await controller.createOrder(
        customer: _customer,
        selection: selection,
      );

      expect(created.number, 'OBM-TEST-0001');
      expect(fake.draft!.items.single.productId, alternative.id);
      expect(fake.draft!.customer.whatsapp, '3001234567');
      expect(fake.draft!.attribution.sellerId, 'DAR');
      expect(fake.draft!.attribution.channelId, 'whatsapp');
      expect(fake.draft!.attribution.campaignId, 'PILOTO-WA-01');
    },
  );

  test(
    'home delivery details reach OrderDraft without shipping charge',
    () async {
      final fake = _FakeOrderRepository();
      final controller = await _controller(fake);
      final selection = OrderSelection.fromPrimary(controller.products.first);
      const details = DeliveryDetails(
        city: 'Bogotá',
        address: 'Calle 10 # 20-30',
        neighborhood: 'Centro',
        recipientName: 'Ana Cliente',
        directions: 'Portería principal',
      );

      await controller.createOrder(
        customer: _customer,
        selection: selection,
        requiresDelivery: true,
        deliveryDetails: details,
      );

      expect(fake.draft!.requiresDelivery, isTrue);
      expect(fake.draft!.deliveryDetails!.city, 'Bogotá');
      expect(fake.draft!.deliveryDetails!.recipientName, 'Ana Cliente');
      expect(fake.draft!.amounts.shippingCop, 0);
      expect(fake.draft!.shippingStatus, ShippingStatus.pendingQuote);
      expect(fake.draft!.toJson()['deliveryMethod'], 'homeDelivery');
    },
  );

  test(
    'verified complementary is optional and reaches the order repository',
    () async {
      final fake = _FakeOrderRepository();
      final controller = await _controller(fake);
      final primary = controller.products.firstWhere(
        (item) => item.id == 'OB019',
      );
      final candidate = controller.crossSellFor(primary).candidates.first;
      final selection = OrderSelection.fromPrimary(
        primary,
      )..addComplementary(candidate.product, relationId: candidate.relation.id);

      await controller.createOrder(customer: _customer, selection: selection);

      expect(fake.draft!.items, hasLength(2));
      expect(fake.draft!.items.last.productId, candidate.product.id);
      expect(fake.draft!.items.last.crossSellRelationId, candidate.relation.id);
      expect(fake.draft!.amounts.subtotalCop, selection.amounts.subtotalCop);

      selection.removeComplementary(candidate.product.id);
      await controller.createOrder(customer: _customer, selection: selection);
      expect(fake.draft!.items, hasLength(1));
    },
  );

  test(
    'active wheel delegates customer and complete selection to server',
    () async {
      final fake = _FakeWheelOrderRepository();
      final controller = await _controller(fake);
      final primary = controller.products.firstWhere(
        (item) => item.id == 'OB019',
      );
      final candidate = controller.crossSellFor(primary).candidates.first;
      final selection = OrderSelection.fromPrimary(
        primary,
      )..addComplementary(candidate.product, relationId: candidate.relation.id);

      final benefit = await controller.spinWheel(
        customer: _customer,
        selection: selection,
      );

      expect(controller.wheelCampaignActive, isTrue);
      expect(fake.spinItems, hasLength(2));
      expect(fake.spinCustomer!.whatsapp, '3001234567');
      expect(benefit.discountPercent, 10);
      expect(benefit.netProductsCop, 135000);
    },
  );

  test(
    'principal, alternative and cross-sell keep distinct item types',
    () async {
      final fake = _FakeOrderRepository();
      final controller = await _controller(fake);
      final primary = controller.products.firstWhere(
        (item) => item.id == 'OB019',
      );
      final alternative = controller.products.firstWhere(
        (item) => item.id == 'OB020',
      );
      final candidate = controller.crossSellFor(primary).candidates.first;
      final selection = OrderSelection.fromPrimary(primary)
        ..addAlternative(alternative)
        ..addComplementary(
          candidate.product,
          relationId: candidate.relation.id,
        );

      await controller.createOrder(customer: _customer, selection: selection);

      expect(fake.draft!.items, hasLength(3));
      expect(fake.draft!.items[0].itemType, OrderItemType.primary);
      expect(fake.draft!.items[1].itemType, OrderItemType.complementary);
      expect(fake.draft!.items[2].itemType, OrderItemType.other);
      expect(
        fake.draft!.amounts.subtotalCop,
        primary.priceCop + alternative.priceCop + candidate.product.priceCop,
      );
      selection.removeAlternative(alternative.id);
      expect(
        selection.items.any((item) => item.productId == alternative.id),
        isFalse,
      );
    },
  );

  test(
    'technical retry keeps journey and consecutive purchases rotate it',
    () async {
      final fake = _FakeOrderRepository(failNextSubmission: true);
      final controller = await _controller(fake);
      final selection = OrderSelection.fromPrimary(controller.products.first);
      final firstJourney = controller.journeyId;

      await expectLater(
        controller.createOrder(customer: _customer, selection: selection),
        throwsStateError,
      );
      expect(controller.journeyId, firstJourney);
      await controller.createOrder(customer: _customer, selection: selection);
      final secondJourney = controller.journeyId;
      expect(secondJourney, isNot(firstJourney));
      await controller.createOrder(customer: _customer, selection: selection);
      expect(fake.journeyIds, [firstJourney, secondJourney]);

      controller.restart();
      final thirdJourney = controller.journeyId;
      expect(thirdJourney, isNot(secondJourney));
      await controller.createOrder(customer: _customer, selection: selection);
      expect(fake.journeyIds.last, thirdJourney);
    },
  );

  test('new purchase returns to welcome with a fresh journey', () async {
    final controller = await _controller(_FakeOrderRepository());
    final previousJourney = controller.journeyId;
    controller.selectCategory('facial');

    controller.startNewPurchase();

    expect(controller.journeyId, isNot(previousJourney));
    expect(controller.stage, AppStage.welcome);
    expect(controller.selectedCategory, isNull);
    expect(controller.result, isNull);
    expect(controller.answers, isEmpty);
  });

  test(
    'server-unavailable product cannot be recommended or reach OrderDraft',
    () async {
      final fake = _FakeOrderRepository(excludedProductIds: const {'OB063'});
      final controller = await _controller(fake);
      const engine = RecommendationEngine();
      final result = engine.recommend(
        category: 'cabello',
        products: controller.products,
        questions: controller.questions,
        answers: const {
          'cab_necesidad': 'nutricion',
          'cab_tipo': 'rubio',
          'cab_secundaria': 'crecimiento',
          'cab_rutina': 'finalizacion',
        },
      );
      expect(controller.products.any((item) => item.id == 'OB063'), isFalse);
      expect(result.primary?.product.id, isNot('OB063'));
      expect(result.alternative?.product.id, isNot('OB063'));

      final localProducts = await const LocalCatalogRepository().loadProducts();
      final selection = OrderSelection.fromPrimary(
        localProducts.firstWhere((item) => item.id == 'OB049'),
      )..addAlternative(localProducts.firstWhere((item) => item.id == 'OB063'));
      await expectLater(
        controller.createOrder(customer: _customer, selection: selection),
        throwsA(isA<OrderSubmissionUnavailable>()),
      );
      expect(fake.draft, isNull);
    },
  );

  test(
    'availability failure closes recommendations and supports retry',
    () async {
      final fake = _FakeOrderRepository(availabilityFailure: true);
      final controller = await _controller(fake);
      expect(controller.availabilityVerified, isFalse);
      expect(controller.products, isEmpty);

      fake.availabilityFailure = false;
      final retry = controller.retryAvailability();
      final duplicateTap = controller.retryAvailability();
      expect(controller.loading, isTrue);
      expect(controller.availabilityError, isNull);
      await Future.wait([retry, duplicateTap]);
      expect(controller.availabilityVerified, isTrue);
      expect(controller.products, isNotEmpty);
      expect(controller.loading, isFalse);
      expect(fake.availabilityChecks, 2);

      fake.availabilityFailure = true;
      await controller.retryAvailability();
      expect(controller.availabilityVerified, isFalse);
      expect(controller.availabilityError, isNotNull);
      expect(fake.availabilityChecks, 3);
    },
  );

  test(
    'suggested kits never become purchasable products or order items',
    () async {
      final fake = _FakeOrderRepository();
      final controller = await _controller(fake);
      expect(controller.products.any((item) => item.isSuggestedKit), isFalse);

      final result = const RecommendationEngine().recommend(
        category: 'regalos',
        products: controller.products,
        questions: controller.questions,
        answers: const {
          'reg_destinatario': 'no_seguro',
          'reg_tipo': 'corporal',
          'reg_ocasion': 'especial',
          'reg_nivel': 'especial',
        },
      );
      expect(result.hasMatch, isTrue);
      expect(result.primary!.product.isSuggestedKit, isFalse);
      expect(result.alternative!.product.isSuggestedKit, isFalse);

      final localProducts = await const LocalCatalogRepository().loadProducts();
      final officialGift = localProducts.firstWhere(
        (item) => item.category == 'regalos',
      );
      final suggestedKit = _asSuggestedKit(officialGift);
      final selection = OrderSelection.fromPrimary(suggestedKit);
      await expectLater(
        controller.createOrder(customer: _customer, selection: selection),
        throwsA(isA<OrderSubmissionUnavailable>()),
      );
      expect(fake.draft, isNull);
    },
  );

  test(
    'immediate stock is loaded only after ranking without changing it',
    () async {
      final fake = _FakeOrderRepository(immediateStockCodes: const {'60138'});
      final controller = await _controller(fake);
      const answers = {
        'perf_destinatario': 'mujer',
        'perf_aroma': 'dulce',
        'perf_ocasion': 'salida',
        'perf_intensidad': 'intensa',
      };
      final pricesBefore = {
        for (final product in controller.products)
          product.code: product.priceCop,
      };
      final expected = const RecommendationEngine().recommend(
        category: 'perfumeria',
        products: controller.products,
        questions: controller.questions,
        answers: answers,
      );

      await _completePerfumeQuiz(controller, answers);

      expect(
        controller.result!.primary!.product.id,
        expected.primary!.product.id,
      );
      expect(
        controller.result!.alternative!.product.id,
        expected.alternative!.product.id,
      );
      expect(controller.hasImmediateStock('60138'), isTrue);
      expect(controller.hasImmediateStock('CODIGO-SIN-INVENTARIO'), isFalse);
      expect(fake.requestedImmediateStockCodes, {
        controller.result!.primary!.product.code,
        controller.result!.alternative!.product.code,
      });
      expect({
        for (final product in controller.products)
          product.code: product.priceCop,
      }, pricesBefore);
    },
  );

  test('immediate stock RPC failure never blocks a recommendation', () async {
    final fake = _FakeOrderRepository(immediateStockFailure: true);
    final controller = await _controller(fake);

    await _completePerfumeQuiz(controller, const {
      'perf_destinatario': 'mujer',
      'perf_aroma': 'dulce',
      'perf_ocasion': 'salida',
      'perf_intensidad': 'intensa',
    });

    expect(controller.result!.hasMatch, isTrue);
    expect(controller.stage, AppStage.result);
    expect(
      controller.hasImmediateStock(controller.result!.primary!.product.code),
      isFalse,
    );
  });

  test('incomplete immediate stock data is handled as no label', () async {
    final fake = _FakeOrderRepository(incompleteImmediateStockResponse: true);
    final controller = await _controller(fake);

    await _completePerfumeQuiz(controller, const {
      'perf_destinatario': 'mujer',
      'perf_aroma': 'dulce',
      'perf_ocasion': 'salida',
      'perf_intensidad': 'intensa',
    });

    expect(controller.result!.hasMatch, isTrue);
    expect(controller.stage, AppStage.result);
    expect(
      controller.hasImmediateStock(controller.result!.primary!.product.code),
      isFalse,
    );
  });
}

Future<void> _completePerfumeQuiz(
  AppController controller,
  Map<String, String> answers,
) async {
  controller.selectCategory('perfumeria');
  for (final entry in answers.entries) {
    expect(controller.currentQuestion!.id, entry.key);
    controller.selectAnswer(
      controller.currentQuestion!.options.firstWhere(
        (option) => option.id == entry.value,
      ),
    );
    await controller.continueQuestion();
  }
}

Product _asSuggestedKit(Product product) => Product(
  id: 'TEST-SUGGESTED-KIT',
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
  code: 'TEST-SUGGESTED-KIT',
  updated: product.updated,
  role: product.role,
  isSuggestedKit: true,
  imagePath: product.imagePath,
);

const _customer = CustomerDraft(
  name: 'Cliente Prueba',
  whatsapp: '3001234567',
  acceptsDataProcessing: true,
  acceptsPromotions: false,
);

Future<AppController> _controller(_FakeOrderRepository repository) async {
  SharedPreferences.setMockInitialValues({});
  final controller = AppController(
    repository: const LocalCatalogRepository(),
    crossSellRepository: const LocalCrossSellRepository(),
    orderRepository: repository,
    analytics: LocalAnalyticsService(),
    attribution: const AttributionContext(
      sellerId: 'DAR',
      channelId: 'whatsapp',
      source: 'whatsapp',
      campaignId: 'PILOTO-WA-01',
    ),
  );
  await controller.initialize();
  return controller;
}

class _FakeOrderRepository
    implements
        OrderRepository,
        ProductAvailabilityRepository,
        ImmediateStockRepository {
  _FakeOrderRepository({
    this.excludedProductIds = const {},
    this.availabilityFailure = false,
    this.failNextSubmission = false,
    this.immediateStockCodes = const {},
    this.immediateStockFailure = false,
    this.incompleteImmediateStockResponse = false,
  });

  final Set<String> excludedProductIds;
  bool availabilityFailure;
  int availabilityChecks = 0;
  bool failNextSubmission;
  final Set<String> immediateStockCodes;
  final bool immediateStockFailure;
  final bool incompleteImmediateStockResponse;
  Set<String>? requestedImmediateStockCodes;
  OrderDraft? draft;
  final List<String> journeyIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> loadPurchasableProductIds() async {
    availabilityChecks++;
    if (availabilityFailure) throw StateError('availability unavailable');
    return (await const LocalCatalogRepository().loadProducts())
        .where(
          (product) =>
              !product.isSuggestedKit &&
              !excludedProductIds.contains(product.id),
        )
        .map((product) => product.id)
        .toSet();
  }

  @override
  Future<Set<String>> loadImmediateStockCodes(Set<String> codes) async {
    requestedImmediateStockCodes = codes;
    if (immediateStockFailure) throw StateError('immediate stock unavailable');
    if (incompleteImmediateStockResponse) {
      throw const FormatException('Respuesta incompleta de inventario físico.');
    }
    return codes.intersection(immediateStockCodes);
  }

  @override
  Future<CreatedOrder> createOrder(OrderDraft draft) async {
    if (failNextSubmission) {
      failNextSubmission = false;
      throw StateError('temporary failure');
    }
    this.draft = draft;
    journeyIds.add(draft.journeyId);
    return const CreatedOrder(
      id: '00000000-0000-0000-0000-000000000001',
      number: 'OBM-TEST-0001',
      status: OrderStatus.requested,
    );
  }
}

class _FakeWheelOrderRepository extends _FakeOrderRepository
    implements WheelRepository {
  CustomerDraft? spinCustomer;
  List<OrderItemDraft>? spinItems;

  @override
  Future<WheelCampaignStatus> loadWheelCampaignStatus() async =>
      const WheelCampaignStatus(active: true);

  @override
  Future<WheelBenefit> spinWheel({
    required String journeyId,
    required CustomerDraft customer,
    required List<OrderItemDraft> items,
  }) async {
    spinCustomer = customer;
    spinItems = items;
    return const WheelBenefit(
      spinId: '00000000-0000-0000-0000-000000000099',
      discountPercent: 10,
      productsCop: 150000,
      discountCop: 15000,
      netProductsCop: 135000,
    );
  }
}
