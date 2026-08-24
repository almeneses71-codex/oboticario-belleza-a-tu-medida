import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/repositories/order_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('manual selection drives the exact validated local summary', (
    tester,
  ) async {
    final orders = _FakeOrderRepository();
    await _openPerfumeResult(tester, orders);

    await _selectProduct(tester, 'Egeo Dolce EDT');
    await tester.ensureVisible(find.text('Continuar con mi elección'));
    await tester.tap(find.text('Continuar con mi elección'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa tu nombre.'), findsOneWidget);
    expect(find.text('Ingresa tu número de WhatsApp.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre'),
      'Ana Cliente',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Número de WhatsApp'),
      '+57 300-123-4567',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Resumen de tu solicitud'), findsOneWidget);
    final firstSummary = find.byType(BottomSheet);
    expect(
      find.descendant(of: firstSummary, matching: find.text('Egeo Dolce EDT')),
      findsOneWidget,
    );
    expect(find.textContaining('SKU: 60138'), findsOneWidget);
    expect(find.text('573001234567'), findsOneWidget);
    expect(find.byKey(const ValueKey('summary-image-OB001')), findsOneWidget);
    expect(find.byKey(const Key('summary-totals-card')), findsOneWidget);
    expect(find.text('TOTAL A PAGAR'), findsOneWidget);
    await tester.ensureVisible(find.text('Enviar mi solicitud'));
    await tester.tap(find.text('Enviar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('OBM-TEST-0001'), findsOneWidget);
    expect(orders.draft!.items.single.productId, 'OB001');

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    final alternativeAction = find.widgetWithText(
      FilledButton,
      'Me interesa este producto',
    );
    expect(alternativeAction, findsOneWidget);
    await tester.ensureVisible(alternativeAction);
    await tester.tap(alternativeAction);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar con mi elección'));
    await tester.tap(find.text('Continuar con mi elección'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre'),
      'Ana Cliente',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Número de WhatsApp'),
      '573001234567',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    final secondSummary = find.byType(BottomSheet);
    expect(
      find.descendant(of: secondSummary, matching: find.text('Egeo Dolce EDT')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondSummary, matching: find.textContaining('SKU:')),
      findsNWidgets(2),
    );
    expect(find.byKey(const ValueKey('summary-image-OB001')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'summary-image-',
            ),
      ),
      findsNWidgets(2),
    );
    await tester.ensureVisible(find.text('Enviar mi solicitud'));
    await tester.tap(find.text('Enviar mi solicitud'));
    await tester.pumpAndSettle();
    expect(orders.draft!.items, hasLength(2));
    expect(orders.draft!.items.first.productId, 'OB001');
    expect(orders.draft!.items.first.itemType, OrderItemType.primary);
    expect(orders.draft!.items.last.itemType, OrderItemType.other);
  });
}

Future<void> _openPerfumeResult(
  WidgetTester tester,
  OrderRepository orderRepository,
) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    BeautyAdvisorApp(
      repository: const LocalCatalogRepository(),
      crossSellRepository: const LocalCrossSellRepository(),
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
    implements OrderRepository, ProductAvailabilityRepository {
  OrderDraft? draft;

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> loadPurchasableProductIds() async =>
      (await const LocalCatalogRepository().loadProducts())
          .map((product) => product.id)
          .toSet();

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
