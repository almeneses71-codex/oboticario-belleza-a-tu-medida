import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app_controller.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/attribution_context.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/customer_draft.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order_selection.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/order_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/recommendation_engine.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'verified complementary is optional and reaches the order repository',
    () async {
      final fake = _FakeOrderRepository();
      final controller = await _controller(fake);
      final primary = controller.products.firstWhere(
        (item) => item.id == 'OB017',
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
        (item) => item.id == 'OB017',
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
        (item) => item.id == 'OB017',
      );
      final alternative = controller.products.firstWhere(
        (item) => item.id == 'OB018',
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
    'restart creates a new journey while retries keep the current one',
    () async {
      final fake = _FakeOrderRepository();
      final controller = await _controller(fake);
      final selection = OrderSelection.fromPrimary(controller.products.first);
      final firstJourney = controller.journeyId;

      await controller.createOrder(customer: _customer, selection: selection);
      await controller.createOrder(customer: _customer, selection: selection);
      expect(fake.journeyIds, [firstJourney, firstJourney]);

      controller.restart();
      final secondJourney = controller.journeyId;
      expect(secondJourney, isNot(firstJourney));
      await controller.createOrder(customer: _customer, selection: selection);
      expect(fake.journeyIds.last, secondJourney);
    },
  );

  test(
    'server-unavailable product cannot be recommended or reach OrderDraft',
    () async {
      final fake = _FakeOrderRepository(excludedProductIds: const {'OB064'});
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
      expect(controller.products.any((item) => item.id == 'OB063'), isTrue);
      expect(controller.products.any((item) => item.id == 'OB064'), isFalse);
      expect(result.primary?.product.id, isNot('OB064'));
      expect(result.alternative?.product.id, 'OB051');

      final localProducts = await const LocalCatalogRepository().loadProducts();
      final selection = OrderSelection.fromPrimary(
        localProducts.firstWhere((item) => item.id == 'OB063'),
      )..addAlternative(localProducts.firstWhere((item) => item.id == 'OB064'));
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
      await controller.retryAvailability();
      expect(controller.availabilityVerified, isTrue);
      expect(controller.products, isNotEmpty);
    },
  );
}

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
    implements OrderRepository, ProductAvailabilityRepository {
  _FakeOrderRepository({
    this.excludedProductIds = const {},
    this.availabilityFailure = false,
  });

  final Set<String> excludedProductIds;
  bool availabilityFailure;
  OrderDraft? draft;
  final List<String> journeyIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> loadPurchasableProductIds() async {
    if (availabilityFailure) throw StateError('availability unavailable');
    return (await const LocalCatalogRepository().loadProducts())
        .where((product) => !excludedProductIds.contains(product.id))
        .map((product) => product.id)
        .toSet();
  }

  @override
  Future<CreatedOrder> createOrder(OrderDraft draft) async {
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
