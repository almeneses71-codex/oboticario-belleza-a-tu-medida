import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('complete perfume recommendation flow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      BeautyAdvisorApp(
        repository: const LocalCatalogRepository(),
        crossSellRepository: const LocalCrossSellRepository(),
        orderRepository: null,
        analytics: LocalAnalyticsService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Comenzar mi diagnóstico'));
    await tester.tap(find.text('Comenzar mi diagnóstico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfumería'));
    await tester.pumpAndSettle();

    final answers = [
      'Para mujer',
      'Dulce y romántica',
      'Todos los días',
      'Marcante',
      'Hasta \$175.000',
    ];
    for (var index = 0; index < answers.length; index++) {
      final answer = answers[index];
      expect(find.text('Pregunta ${index + 1} de 5'), findsOneWidget);
      await tester.ensureVisible(find.text(answer));
      await tester.tap(find.text(answer));
      await tester.pumpAndSettle();
      final continueLabel = index == 4 ? 'Ver mi recomendación' : 'Continuar';
      await tester.ensureVisible(find.text(continueLabel));
      await tester.tap(find.text(continueLabel));
      if (index == 4) {
        await tester.pump();
        expect(
          find.text('Estamos encontrando tu mejor opción'),
          findsOneWidget,
        );
      }
      await tester.pumpAndSettle();
    }

    expect(find.text('Tu recomendación principal'), findsOneWidget);
    expect(find.text('Otra opción para ti'), findsOneWidget);
    expect(find.text('Me interesa este producto'), findsNWidgets(2));
    expect(find.text('Quiero asesoría'), findsOneWidget);

    final productAction = find.text('Me interesa este producto').first;
    await tester.ensureVisible(productAction);
    await tester.tap(productAction);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar con mi elección'));
    await tester.tap(find.text('Continuar con mi elección'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre'),
      'Cliente Prueba',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Número de WhatsApp'),
      '573001234567',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Revisar mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Resumen de tu solicitud'), findsOneWidget);
    expect(find.text('Enviar mi solicitud'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enviar mi solicitud'),
          )
          .onPressed,
      isNull,
    );
  });
}
