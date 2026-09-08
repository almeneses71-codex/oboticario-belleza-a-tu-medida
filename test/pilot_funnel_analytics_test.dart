import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/app_controller.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_catalog_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/data/local_cross_sell_repository.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/attribution_context.dart';
import 'package:oboticario_belleza_a_tu_medida/domain/models/order.dart';
import 'package:oboticario_belleza_a_tu_medida/services/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'six funnel milestones keep one journey and public attribution',
    () async {
      final analytics = _RecordingAnalytics();
      const attribution = AttributionContext(
        sellerId: 'DAR',
        channelId: 'whatsapp',
        source: 'whatsapp',
        campaignId: 'AMOR_AMISTAD_2026',
      );
      final controller = AppController(
        repository: const LocalCatalogRepository(),
        crossSellRepository: const LocalCrossSellRepository(),
        orderRepository: null,
        analytics: analytics,
        attribution: attribution,
      );

      final journeyId = controller.journeyId;
      await controller.initialize();
      controller.begin();
      controller.selectCategory('cabello');
      while (controller.stage == AppStage.questionnaire) {
        controller.selectAnswer(controller.currentQuestionOptions.first);
        await controller.continueQuestion();
      }
      final recommended = controller.result!.primary!.product;
      controller.recordProductSelected(recommended);
      controller.recordRequestStarted(
        OrderItemDraft(
          productId: recommended.id,
          productCode: recommended.code,
          productName: recommended.name,
          itemType: OrderItemType.primary,
          quantity: 1,
          originalUnitPriceCop: recommended.priceCop,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(analytics.events.map((event) => event.eventType), [
        'app_open',
        'diagnosis_started',
        'diagnosis_completed',
        'recommendation_viewed',
        'product_selected',
        'request_started',
      ]);
      expect(
        analytics.events.every((event) => event.journeyId == journeyId),
        isTrue,
      );
      expect(
        analytics.events.every((event) => event.attribution == attribution),
        isTrue,
      );
      expect(
        analytics.events
            .where((event) => event.productId != null)
            .every(
              (event) =>
                  event.productId == recommended.id &&
                  event.productCode == recommended.code,
            ),
        isTrue,
      );
    },
  );

  test('analytics failure never blocks the customer journey', () async {
    final controller = AppController(
      repository: const LocalCatalogRepository(),
      crossSellRepository: const LocalCrossSellRepository(),
      orderRepository: null,
      analytics: _FailingAnalytics(),
    );

    await controller.initialize();
    controller.begin();
    controller.selectCategory('cabello');
    controller.selectAnswer(controller.currentQuestionOptions.first);
    await controller.continueQuestion();
    await Future<void>.delayed(Duration.zero);

    expect(controller.stage, AppStage.questionnaire);
    expect(controller.questionIndex, 1);
    expect(controller.error, isNull);
  });
}

class _RecordedFunnelEvent {
  const _RecordedFunnelEvent({
    required this.eventType,
    required this.journeyId,
    required this.attribution,
    this.productId,
    this.productCode,
  });

  final String eventType;
  final String journeyId;
  final AttributionContext attribution;
  final String? productId;
  final String? productCode;
}

class _RecordingAnalytics implements AnalyticsService {
  final List<_RecordedFunnelEvent> events = [];

  @override
  Future<void> recordFunnelEvent({
    required String eventType,
    required String journeyId,
    required AttributionContext attribution,
    String? productId,
    String? productCode,
  }) async {
    events.add(
      _RecordedFunnelEvent(
        eventType: eventType,
        journeyId: journeyId,
        attribution: attribution,
        productId: productId,
        productCode: productCode,
      ),
    );
  }

  @override
  Future<void> recordAppOpen() async {}
  @override
  Future<void> recordQuizCompleted(String category, String? productId) async {}
  @override
  Future<void> recordWhatsappClick(String? productId) async {}
  @override
  Future<void> recordCrossSellShown({
    required String journeyId,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  }) async {}
  @override
  Future<void> recordComplementaryChanged({
    required String journeyId,
    required bool added,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  }) async {}
  @override
  Future<Map<String, int>> getCounters() async => const {};
}

class _FailingAnalytics extends _RecordingAnalytics {
  @override
  Future<void> recordFunnelEvent({
    required String eventType,
    required String journeyId,
    required AttributionContext attribution,
    String? productId,
    String? productCode,
  }) => Future<void>.error(StateError('analytics unavailable'));
}
