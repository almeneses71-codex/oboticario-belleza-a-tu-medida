import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app_controller.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/attribution_context.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/customer_draft.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order_selection.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/order_repository.dart';
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

class _FakeOrderRepository implements OrderRepository {
  OrderDraft? draft;

  @override
  bool get isConfigured => true;

  @override
  Future<CreatedOrder> createOrder(OrderDraft draft) async {
    this.draft = draft;
    return const CreatedOrder(
      id: '00000000-0000-0000-0000-000000000001',
      number: 'OBM-TEST-0001',
      status: OrderStatus.requested,
    );
  }
}
