import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/customer_draft.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/cross_sell_relation.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/product.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/question.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/order_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CachedCatalogRepository catalogRepository;
  late _CachedCrossSellRepository crossSellRepository;
  late Set<String> availableIds;

  setUpAll(() async {
    final localCatalog = const LocalCatalogRepository();
    final products = await localCatalog.loadProducts();
    catalogRepository = _CachedCatalogRepository(
      products,
      await localCatalog.loadQuestions(),
    );
    crossSellRepository = _CachedCrossSellRepository(
      await const LocalCrossSellRepository().loadRelations(),
    );
    availableIds = products.map((product) => product.id).toSet();
  });

  testWidgets(
    'summary shows three products and active wheel on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final repository = _FakeWheelOrderRepository(availableIds);
      await tester.pumpWidget(
        BeautyAdvisorApp(
          repository: catalogRepository,
          crossSellRepository: crossSellRepository,
          orderRepository: repository,
          analytics: LocalAnalyticsService(),
        ),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, 'Comenzar mi diagnóstico');
      await _tapVisible(tester, 'Cuidado corporal');
      for (final answer in [
        'No estoy seguro',
        'Hidratar',
        'Loción',
        'Hidratación prolongada',
      ]) {
        await _tapVisible(tester, answer);
        await _tapVisible(
          tester,
          answer == 'Hidratación prolongada'
              ? 'Ver mi recomendación'
              : 'Continuar',
        );
      }

      expect(
        find.byKey(const Key('explore-selection-guidance')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Selecciona el producto que te interesa para continuar y obtener tu descuento en la ruleta.',
        ),
        findsOneWidget,
      );

      for (var selectedProducts = 0; selectedProducts < 2; selectedProducts++) {
        final productAction = find.widgetWithText(
          FilledButton,
          'Me interesa este producto',
        );
        expect(productAction, findsWidgets);
        await tester.ensureVisible(productAction.first);
        await tester.tap(productAction.first);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('¿Cómo quieres recibir tu pedido?'), findsNothing);
        
      }
  
      final complement = find.widgetWithText(
        OutlinedButton,
        'Agregar complemento',
      );
      expect(complement, findsWidgets);
      await tester.ensureVisible(complement.first);
      await tester.tap(complement.first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('¿Cómo quieres recibir tu pedido?'), findsNothing);

      
      await _tapVisible(tester, 'Continuar con mi selección');

      final continueToDelivery =
          find.byKey(const Key('continue-to-delivery'));
      expect(continueToDelivery, findsOneWidget);
      await tester.tap(continueToDelivery);
      await tester.pumpAndSettle();

      expect(find.byType(RadioListTile<bool>), findsNWidgets(2));
      await tester.ensureVisible(find.text('Acordar entrega con asesor'));
      await tester.tap(find.text('Acordar entrega con asesor'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Ana Cliente',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número de WhatsApp'),
        '573001234567',
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await _tapVisible(tester, 'Revisar mi solicitud');

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'summary-image-',
              ),
        ),
        findsNWidgets(3),
      );
      expect(find.byKey(const Key('summary-totals-card')), findsOneWidget);
      expect(find.byKey(const Key('wheel-campaign-banner')), findsOneWidget);
      expect(find.byKey(const Key('ready-wheel')), findsOneWidget);
      expect(find.byKey(const Key('wheel-spin-available')), findsOneWidget);
      final spinButton = find.byKey(const Key('wheel-spin-button'));
      expect(tester.getCenter(spinButton).dy, lessThan(568));
      expect(find.byType(RadioListTile<bool>), findsNothing);
      expect(find.text('¿Cómo quieres recibir tu pedido?'), findsNothing);
      expect(find.text('Tipo de envío'), findsOneWidget);
      expect(find.text('Acordar entrega con asesor'), findsOneWidget);
      await tester.ensureVisible(find.text('Girar la ruleta'));
      await tester.tap(find.text('Girar la ruleta'));
      await tester.pump();
      await tester.pump();

      expect(repository.spinCalls, 1);
      expect(find.byKey(const Key('spinning-wheel-panel')), findsOneWidget);
      expect(find.byKey(const Key('spinning-wheel')), findsOneWidget);
      expect(find.byKey(const Key('wheel-benefit-banner')), findsNothing);
      expect(find.byKey(const Key('wheel-spin-button')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-order-button')))
            .onPressed,
        isNull,
      );

      await tester.pump(const Duration(milliseconds: 1900));
      expect(repository.spinCalls, 1);
      expect(find.byKey(const Key('wheel-benefit-banner')), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const Key('wheel-benefit-banner')), findsOneWidget);
      expect(find.byKey(const Key('wheel-spin-available')), findsNothing);
      expect(find.byKey(const Key('wheel-spin-button')), findsNothing);
      expect(
        find.text('¡Felicidades! Ganaste 10% de descuento'),
        findsOneWidget,
      );
      expect(find.text('Descuento Amor y Amistad (10%)'), findsOneWidget);
      expect(find.byKey(const Key('summary-discount-row')), findsOneWidget);
      expect(find.byKey(const Key('summary-total-row')), findsOneWidget);
      await tester.ensureVisible(find.text('TOTAL A PAGAR'));
      await tester.ensureVisible(find.text('Enviar mi solicitud'));
      await tester.tap(find.text('Enviar mi solicitud'));
      await tester.pumpAndSettle();
      expect(find.text('¡Solicitud recibida!'), findsOneWidget);
      expect(find.byKey(const Key('final-order-number')), findsOneWidget);
      expect(find.text('Dario y Ana'), findsOneWidget);
      expect(find.text('¿QUÉ SIGUE?'), findsOneWidget);
      await tester.ensureVisible(find.text('Realizar otra compra'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recommended cards keep a responsive product-first layout',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final size in const [
        Size(360, 760),
        Size(768, 900),
        Size(1366, 900),
      ]) {
        tester.view.physicalSize = size;
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          BeautyAdvisorApp(
            key: ValueKey('responsive-${size.width}'),
            repository: catalogRepository,
            crossSellRepository: crossSellRepository,
            orderRepository: _FakeWheelOrderRepository(availableIds),
            analytics: LocalAnalyticsService(),
          ),
        );
        await tester.pumpAndSettle();

        await _tapVisible(tester, 'Comenzar mi diagnóstico');
        await _tapVisible(tester, 'Cuidado corporal');
        for (final answer in [
          'No estoy seguro',
          'Hidratar',
          'Loción',
          'Hidratación prolongada',
        ]) {
          await _tapVisible(tester, answer);
          await _tapVisible(
            tester,
            answer == 'Hidratación prolongada'
                ? 'Ver mi recomendación'
                : 'Continuar',
          );
        }

        final cards = find.byWidgetPredicate(
          (widget) =>
              widget is Card &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'recommended-product-card-',
              ),
        );
        final images = find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'product-image-',
              ),
        );

        expect(cards, findsNWidgets(2));
        expect(images, findsNWidgets(2));
        expect(
          find.text(
            'Cuidado experto para una piel más saludable y radiante',
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Me interesa este producto'),
          findsNWidgets(2),
        );
        expect(
          find.text(
            'Al continuar podrás obtener tu descuento en la ruleta.',
          ),
          findsNWidgets(2),
        );
        expect(tester.getSize(images.first).height, greaterThanOrEqualTo(280));
        if (size.width >= 768) {
          expect(tester.getSize(cards.first).width, greaterThan(700));
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

class _FakeWheelOrderRepository
    implements OrderRepository, ProductAvailabilityRepository, WheelRepository {
  _FakeWheelOrderRepository(this.availableIds);

  final Set<String> availableIds;
  int spinCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> loadPurchasableProductIds() async => availableIds;

  @override
  Future<WheelCampaignStatus> loadWheelCampaignStatus() async =>
      const WheelCampaignStatus(active: true);

  @override
  Future<WheelBenefit> spinWheel({
    required String journeyId,
    required CustomerDraft customer,
    required List<OrderItemDraft> items,
  }) async {
    spinCalls++;
    final productsCop = items.fold<int>(
      0,
      (total, item) => total + (item.originalUnitPriceCop * item.quantity),
    );
    final discountCop = (productsCop * 0.1).round();
    final netProductsCop =
        (((productsCop - discountCop) + 50) / 100).floor() * 100;
    return WheelBenefit(
      spinId: 'wheel-test',
      discountPercent: 10,
      productsCop: productsCop,
      discountCop: discountCop,
      netProductsCop: netProductsCop,
    );
  }

  @override
  Future<CreatedOrder> createOrder(OrderDraft draft) async =>
      const CreatedOrder(
        id: '00000000-0000-0000-0000-000000000001',
        number: 'OBM-TEST-0001',
        status: OrderStatus.requested,
      );
}

class _CachedCatalogRepository implements CatalogRepository {
  const _CachedCatalogRepository(this.products, this.questions);

  final List<Product> products;
  final List<Question> questions;

  @override
  Future<List<Product>> loadProducts() async => products;

  @override
  Future<List<Question>> loadQuestions() async => questions;
}

class _CachedCrossSellRepository implements CrossSellRepository {
  const _CachedCrossSellRepository(this.relations);

  final List<CrossSellRelation> relations;

  @override
  Future<List<CrossSellRelation>> loadRelations() async => relations;
}
