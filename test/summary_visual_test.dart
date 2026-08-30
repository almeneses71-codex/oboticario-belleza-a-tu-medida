import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/customer_draft.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/order_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'summary shows three products and active wheel on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final repository = _FakeWheelOrderRepository();
      await tester.pumpWidget(
        BeautyAdvisorApp(
          repository: const LocalCatalogRepository(),
          crossSellRepository: const LocalCrossSellRepository(),
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

      for (var selectedProducts = 0; selectedProducts < 2; selectedProducts++) {
        final productAction = find.widgetWithText(
          FilledButton,
          'Me interesa este producto',
        );
        expect(productAction, findsWidgets);
        await tester.ensureVisible(productAction.first);
        await tester.tap(productAction.first);
        await tester.pumpAndSettle();
      }
      final complement = find.widgetWithText(
        OutlinedButton,
        'Agregar complemento',
      );
      expect(complement, findsWidgets);
      await tester.ensureVisible(complement.first);
      await tester.tap(complement.first);
      await tester.pumpAndSettle();

      await _tapVisible(tester, 'Continuar con mi elección');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Ana Cliente',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número de WhatsApp'),
        '573001234567',
      );
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
      await _tapVisible(tester, 'Acordar entrega con asesor');
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
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

class _FakeWheelOrderRepository
    implements OrderRepository, ProductAvailabilityRepository, WheelRepository {
  int spinCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> loadPurchasableProductIds() async =>
      (await const LocalCatalogRepository().loadProducts())
          .map((product) => product.id)
          .toSet();

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
