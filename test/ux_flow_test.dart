import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
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

  testWidgets('manual selection drives the exact validated local summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final orders = _FakeOrderRepository(
      availableIds,
      immediateStockCodes: const {'60138'},
    );
    await _openPerfumeResult(
      tester,
      orders,
      catalogRepository,
      crossSellRepository,
    );
    expect(find.text('Entrega inmediata'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('immediate-delivery-60138')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('immediate-delivery-63413')),
      findsNothing,
    );
    
    
    
    await _selectProduct(
      tester,
      'Perfume para mujer Egeo dolce EDT 90Ml',
    );

    final continueWithSelection = find.text('Continuar con mi selección');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('¿Cómo quieres recibir tu pedido?'), findsNothing);
    await tester.ensureVisible(continueWithSelection);
    await tester.tap(continueWithSelection);
    await tester.pumpAndSettle();

    expect(find.text('¡Excelente elección!'), findsOneWidget);

    expect(
      find.text(
        'Ya elegiste tus productos.\nAhora dinos cómo quieres recibir tu pedido.',
      ),
      findsOneWidget,
    );
    final continueToDelivery = find.byKey(const Key('continue-to-delivery'));
    expect(continueToDelivery.hitTestable(), findsOneWidget);
    await tester.tap(continueToDelivery);
    await tester.pumpAndSettle();
    expect(find.text('Último paso · Entrega').hitTestable(), findsOneWidget);
    expect(
      find.text('¿Cómo quieres recibir tu pedido?').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Envío a domicilio').hitTestable(), findsOneWidget);
    expect(
      find.text('Acordar entrega con asesor').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(RadioListTile<bool>), findsNWidgets(2));
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Nombre'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre'),
      'Ana Cliente',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Número de WhatsApp'),
      '+57 300-123-4567',
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.text('Revisar mi solicitud'));
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Resumen de tu solicitud'), findsNothing);
    await tester.ensureVisible(find.text('Envío a domicilio'));
    await tester.tap(find.text('Envío a domicilio'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Revisar mi solicitud'));
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Resumen de tu solicitud'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ciudad/municipio'),
      'Bogotá',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Dirección'),
      'Calle 10 # 20-30',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Barrio'), 'Centro');
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de quien recibe'),
      'Ana Cliente',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Revisar mi solicitud'));
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Resumen de tu solicitud'), findsOneWidget);
    expect(find.byType(RadioListTile<bool>), findsNothing);
    expect(find.text('¿Cómo quieres recibir tu pedido?'), findsNothing);
    expect(find.text('Tipo de envío'), findsOneWidget);
    expect(find.text('Envío a domicilio · costo por confirmar'), findsOneWidget);
    final firstSummary = find.byType(BottomSheet);
    expect(
      find.descendant(
        of: firstSummary,
        matching: find.text('Perfume para mujer Egeo dolce EDT 90Ml'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('SKU: 60138'), findsOneWidget);
    expect(find.byKey(const ValueKey('summary-image-OB001')), findsOneWidget);
    expect(find.byKey(const Key('summary-totals-card')), findsOneWidget);
    expect(find.text('TOTAL A PAGAR'), findsOneWidget);
    await tester.ensureVisible(find.text('Enviar mi solicitud'));
    await tester.tap(find.text('Enviar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('OBM-TEST-0001'), findsOneWidget);
    expect(find.text('¡Solicitud recibida!'), findsOneWidget);
    expect(find.text('Dario y Ana'), findsOneWidget);
    expect(find.text('¿QUÉ SIGUE?'), findsOneWidget);
    expect(find.text('Continuar por WhatsApp'), findsOneWidget);
    expect(find.text('Realizar otra compra'), findsOneWidget);
    expect(orders.draft!.items.single.productId, 'OB001');
    expect(orders.draft!.requiresDelivery, isTrue);
    expect(orders.draft!.deliveryDetails!.city, 'Bogotá');
    await tester.ensureVisible(find.text('Realizar otra compra'));
    await tester.tap(find.text('Realizar otra compra'));
    await tester.pumpAndSettle();
    expect(find.text('Comenzar mi diagnóstico'), findsOneWidget);
    expect(find.text('¡Solicitud recibida!'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openPerfumeResult(
  WidgetTester tester,
  OrderRepository orderRepository,
  CatalogRepository catalogRepository,
  CrossSellRepository crossSellRepository,
) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    BeautyAdvisorApp(
      repository: catalogRepository,
      crossSellRepository: crossSellRepository,
      orderRepository: orderRepository,
      analytics: LocalAnalyticsService(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Comenzar mi diagnóstico'));
  await tester.tap(find.text('Comenzar mi diagnóstico'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Perfumería'));
  await tester.pumpAndSettle();
  for (final answer in [
    'Para mujer',
    'Dulce',
    'Salidas o eventos',
    'Intensa',
  ]) {
    await tester.ensureVisible(find.text(answer));
    await tester.tap(find.text(answer));
    await tester.pumpAndSettle();
    final last = answer == 'Intensa';
    final label = last ? 'Ver mi recomendación' : 'Continuar';
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }
}

class _FakeOrderRepository
    implements
        OrderRepository,
        ProductAvailabilityRepository,
        ImmediateStockRepository {
  _FakeOrderRepository(
    this.availableIds, {
    this.immediateStockCodes = const {},
  });

  final Set<String> availableIds;
  final Set<String> immediateStockCodes;
  OrderDraft? draft;
  final List<String> journeyIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> loadPurchasableProductIds() async => availableIds;

  @override
  Future<Set<String>> loadImmediateStockCodes(Set<String> codes) async =>
      codes.intersection(immediateStockCodes);

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

Future<void> _selectProduct(WidgetTester tester, String name) async {
  final card = find
      .ancestor(of: find.text(name), matching: find.byType(Card))
      .first;
  final action = find.descendant(
    of: card,
    matching: find.widgetWithText(FilledButton, 'Me interesa este producto'),
  );
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}
