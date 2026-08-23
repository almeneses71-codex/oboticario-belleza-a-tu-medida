import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('manual selection drives the exact validated local summary', (
    tester,
  ) async {
    await _openPerfumeResult(tester);

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
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Resumen de tu solicitud'), findsOneWidget);
    final firstSummary = find.byType(BottomSheet);
    expect(
      find.descendant(of: firstSummary, matching: find.text('Egeo Dolce EDT')),
      findsOneWidget,
    );
    expect(find.text('60138'), findsOneWidget);
    expect(find.text('573001234567'), findsOneWidget);

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
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    final secondSummary = find.byType(BottomSheet);
    expect(
      find.descendant(of: secondSummary, matching: find.text('Egeo Dolce EDT')),
      findsNothing,
    );
    expect(
      find.descendant(of: secondSummary, matching: find.text('Código/SKU')),
      findsOneWidget,
    );
  });
}

Future<void> _openPerfumeResult(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    BeautyAdvisorApp(
      repository: const LocalCatalogRepository(),
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
    'Dulce y romántica',
    'Todos los días',
    'Marcante',
    'Hasta \$175.000',
  ]) {
    await tester.ensureVisible(find.text(answer));
    await tester.tap(find.text(answer));
    await tester.pumpAndSettle();
    final last = answer == r'Hasta $175.000';
    final label = last ? 'Ver mi recomendación' : 'Continuar';
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
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
