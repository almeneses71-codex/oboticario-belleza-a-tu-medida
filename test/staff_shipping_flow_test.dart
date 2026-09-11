import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/staff_app.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/staff_order.dart';

void main() {
  testWidgets('shipping dialog keeps customer modality read-only', (
    tester,
  ) async {
    final order = StaffOrder(
      id: 'order-1',
      number: 'OB-1',
      status: 'availability_verified',
      customerName: 'Cliente',
      customerWhatsapp: '3001234567',
      customerRequiresDelivery: true,
      subtotalCop: 100000,
      discountCop: 0,
      shippingCop: 0,
      shippingStatus: 'pending_quote',
      createdAt: DateTime(2026, 9, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StaffOrderCard(
              order: order,
              busy: false,
              onAdvance: () {},
              onShipping: (_, __) {},
              onCancel: (_) {},
              assignableSellers: const [],
              onAssign: (_, __) {},
              onCreateFollowup: (_, __) async => true,
              onCompleteFollowup: (_, __) {},
              onAuthorizeContact: () async => true,
              onVerifyAvailability: (_, __) {},
              onRecordCustomerAcceptance: (_, __) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OB-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar datos de envío'));
    await tester.pumpAndSettle();

    expect(find.text('Modalidad elegida por el cliente'), findsOneWidget);
    expect(find.text('Domicilio solicitado por el cliente'), findsOneWidget);
    expect(find.text('Empresa de envío / transportadora'), findsOneWidget);
    expect(find.text('Costo de envío del pedido'), findsOneWidget);
    expect(find.text('¿Este pedido requiere domicilio?'), findsNothing);
    expect(find.text('Definir entrega'), findsNothing);
  });
}
