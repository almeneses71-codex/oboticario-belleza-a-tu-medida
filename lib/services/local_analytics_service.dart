import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/attribution_context.dart';
import 'analytics_service.dart';

class LocalAnalyticsService implements AnalyticsService {
  static const _opens = 'metric_app_opens';
  static const _completed = 'metric_quiz_completed';
  static const _whatsapp = 'metric_whatsapp_clicks';
  static const _crossSellShown = 'metric_cross_sell_shown';
  static const _complementaryAdded = 'metric_complementary_added';
  static const _complementaryRemoved = 'metric_complementary_removed';

  @override
  Future<Map<String, int>> getCounters() async {
    final preferences = await SharedPreferences.getInstance();
    return {
      'app_opens': preferences.getInt(_opens) ?? 0,
      'quiz_completed': preferences.getInt(_completed) ?? 0,
      'whatsapp_clicks': preferences.getInt(_whatsapp) ?? 0,
      'cross_sell_shown': preferences.getInt(_crossSellShown) ?? 0,
      'complementary_added': preferences.getInt(_complementaryAdded) ?? 0,
      'complementary_removed': preferences.getInt(_complementaryRemoved) ?? 0,
    };
  }

  @override
  Future<void> recordAppOpen() => _increment(_opens);

  @override
  Future<void> recordQuizCompleted(String category, String? productId) =>
      _increment(_completed);

  @override
  Future<void> recordWhatsappClick(String? productId) => _increment(_whatsapp);

  @override
  Future<void> recordFunnelEvent({
    required String eventType,
    required String journeyId,
    required AttributionContext attribution,
    String? productId,
    String? productCode,
  }) async {}

  @override
  Future<void> recordCrossSellShown({
    required String journeyId,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  }) => _increment(_crossSellShown);

  @override
  Future<void> recordComplementaryChanged({
    required String journeyId,
    required bool added,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  }) => _increment(added ? _complementaryAdded : _complementaryRemoved);

  Future<void> _increment(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(key, (preferences.getInt(key) ?? 0) + 1);
  }
}
