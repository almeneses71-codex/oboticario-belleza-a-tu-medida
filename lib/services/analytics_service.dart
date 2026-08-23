import '../domain/models/attribution_context.dart';

abstract interface class AnalyticsService {
  Future<void> recordAppOpen();
  Future<void> recordQuizCompleted(String category, String? productId);
  Future<void> recordWhatsappClick(String? productId);
  Future<void> recordCrossSellShown({
    required String journeyId,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  });
  Future<void> recordComplementaryChanged({
    required String journeyId,
    required bool added,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  });
  Future<Map<String, int>> getCounters();
}
