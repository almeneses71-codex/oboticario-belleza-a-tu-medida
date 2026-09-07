import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/staff_app.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/staff_order.dart';

void main() {
  testWidgets('staff orders display Supabase instants in Colombia time', (
    tester,
  ) async {
    final controller = StaffController(null)
      ..profile = const StaffProfile(
        role: StaffRole.admin,
        displayName: 'Prueba',
      )
      ..totalCount = 2
      ..orders = [
        _order('OBM-260907-WEB-0001', '2026-09-08T03:00:00Z'),
        _order('OBM-260908-WEB-0001', '2026-09-08T05:01:00Z'),
      ];

    await tester.pumpWidget(
      MaterialApp(home: StaffOrdersScreen(controller: controller)),
    );

    expect(find.textContaining('07/09/2026 22:00'), findsOneWidget);
    expect(find.textContaining('08/09/2026 00:01'), findsOneWidget);
  });
}

StaffOrder _order(String number, String createdAt) => StaffOrder(
  id: number,
  number: number,
  status: 'requested',
  customerName: 'Cliente',
  customerWhatsapp: '3001234567',
  subtotalCop: 100000,
  discountCop: 0,
  shippingCop: 0,
  shippingStatus: 'pending_quote',
  createdAt: DateTime.parse(createdAt).toLocal(),
);
