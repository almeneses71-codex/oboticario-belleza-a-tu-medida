import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/app/staff_auth_restore.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/cross_sell_relation.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/product.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/question.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/staff_order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/order_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/staff_repository.dart';
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

  testWidgets('welcome opens the five category selector', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      BeautyAdvisorApp(
        repository: catalogRepository,
        crossSellRepository: crossSellRepository,
        orderRepository: _AvailabilityOnlyRepository(availableIds),
        analytics: LocalAnalyticsService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Belleza a tu medida'), findsOneWidget);
    expect(find.text('Regala belleza, regala emociones'), findsOneWidget);
    expect(find.text('Te acompaña Dario y Ana'), findsOneWidget);
    expect(find.text('Comenzar mi diagnóstico'), findsOneWidget);
    await tester.ensureVisible(find.text('Comenzar mi diagnóstico'));
    await tester.tap(find.text('Comenzar mi diagnóstico'));
    await tester.pumpAndSettle();

    expect(find.text('Perfumería'), findsOneWidget);
    expect(find.text('Cuidado corporal'), findsOneWidget);
    expect(find.text('Cuidado facial'), findsOneWidget);
    expect(find.text('Cabello'), findsOneWidget);
    expect(find.text('Regalos y kits'), findsOneWidget);

    await tester.tap(find.text('Perfumería'));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 2 de 5'), findsOneWidget);
    await tester.tap(find.text('Para mujer'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 3 de 5'), findsOneWidget);
    await tester.ensureVisible(find.text('Atrás'));
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 2 de 5'), findsOneWidget);
  });

  testWidgets('Ana enters order management after a clean Google callback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await StaffAuthRestore.markPending();
    final staffRepository = _DelayedAnaStaffRepository();

    await tester.pumpWidget(
      BeautyAdvisorApp(
        repository: catalogRepository,
        crossSellRepository: crossSellRepository,
        orderRepository: _AvailabilityOnlyRepository(availableIds),
        analytics: LocalAnalyticsService(),
        staffRepository: staffRepository,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Pedidos'), findsOneWidget);
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
    expect(find.text('Belleza a tu medida'), findsNothing);
  });

  testWidgets(
    'restored authorized Google session opens order management directly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        BeautyAdvisorApp(
          repository: catalogRepository,
          crossSellRepository: crossSellRepository,
          orderRepository: _AvailabilityOnlyRepository(availableIds),
          analytics: LocalAnalyticsService(),
          staffRepository: _RestoredStaffRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.text('Hola, Administrador'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsNothing);
      expect(find.text('Belleza a tu medida'), findsNothing);
    },
  );

  for (final configured in [true, false]) {
    testWidgets('administrative access stays at bottom: cloud=$configured', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        BeautyAdvisorApp(
          repository: catalogRepository,
          crossSellRepository: crossSellRepository,
          orderRepository: _AvailabilityOnlyRepository(availableIds),
          analytics: LocalAnalyticsService(),
          staffRepository: configured ? _SignedOutStaffRepository() : null,
        ),
      );
      await tester.pumpAndSettle();
      final access = find.byKey(const Key('temporary-staff-access'));
      expect(access, findsOneWidget);
      expect(access.hitTestable(), findsOneWidget);
      final bounds = tester.getRect(access);
      expect(bounds.top, greaterThan(640 / 2));
      expect(bounds.bottom, lessThanOrEqualTo(640));
      expect(bounds.bottom, greaterThan(640 - 100));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(360));
      await tester.tap(access);
      await tester.pumpAndSettle();
      expect(find.text('Gestión de pedidos'), findsOneWidget);
      expect(
        find.text('El entorno de pedidos no está configurado.'),
        configured ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

class _DelayedAnaStaffRepository implements StaffRepository {
  int _sessionChecks = 0;

  @override
  bool get hasSession => ++_sessionChecks >= 3;

  @override
  bool get isConfigured => true;

  @override
  Future<StaffProfile?> loadCurrentProfile() async =>
      const StaffProfile(role: StaffRole.seller, displayName: 'Ana');

  @override
  Future<StaffOrderPage> loadOrders({
    StaffOrderFilter filter = const StaffOrderFilter(),
  }) async => const StaffOrderPage(orders: [], totalCount: 0);

  @override
  Future<Map<String, int>> loadStatusCounts() async => const {};

  @override
  Future<Map<String, int>> loadAttentionCounts() async => const {};

  @override
  Future<List<StaffSellerOption>> loadAssignableSellers() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RestoredStaffRepository implements StaffRepository {
  @override
  bool get hasSession => true;

  @override
  bool get isConfigured => true;

  @override
  Future<StaffProfile?> loadCurrentProfile() async =>
      const StaffProfile(role: StaffRole.admin, displayName: 'Administrador');

  @override
  Future<StaffOrderPage> loadOrders({
    StaffOrderFilter filter = const StaffOrderFilter(),
  }) async => const StaffOrderPage(orders: [], totalCount: 0);

  @override
  Future<Map<String, int>> loadStatusCounts() async => const {};

  @override
  Future<Map<String, int>> loadAttentionCounts() async => const {};

  @override
  Future<List<StaffSellerOption>> loadAssignableSellers() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOutStaffRepository implements StaffRepository {
  @override
  bool get hasSession => false;

  @override
  bool get isConfigured => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _AvailabilityOnlyRepository
    implements OrderRepository, ProductAvailabilityRepository {
  const _AvailabilityOnlyRepository(this.availableIds);

  final Set<String> availableIds;

  @override
  bool get isConfigured => false;

  @override
  Future<Set<String>> loadPurchasableProductIds() async => availableIds;

  @override
  Future<CreatedOrder> createOrder(OrderDraft draft) =>
      throw const OrderSubmissionUnavailable();
}
