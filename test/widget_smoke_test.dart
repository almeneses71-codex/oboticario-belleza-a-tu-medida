import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/services/local_analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('welcome opens the five category selector', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      BeautyAdvisorApp(
        repository: const LocalCatalogRepository(),
        analytics: LocalAnalyticsService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Belleza a tu medida'), findsOneWidget);
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
    expect(find.text('Pregunta 1 de 5'), findsOneWidget);
    await tester.tap(find.text('Para mujer'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 2 de 5'), findsOneWidget);
    await tester.ensureVisible(find.text('Atrás'));
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 1 de 5'), findsOneWidget);
  });
}
