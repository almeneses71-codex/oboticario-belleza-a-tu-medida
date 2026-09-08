import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/attribution_context.dart';
import 'analytics_service.dart';

class SupabaseAnalyticsService implements AnalyticsService {
  const SupabaseAnalyticsService(this._client, this._local);

  final SupabaseClient _client;
  final AnalyticsService _local;

  @override
  Future<Map<String, int>> getCounters() => _local.getCounters();

  @override
  Future<void> recordAppOpen() => _local.recordAppOpen();

  @override
  Future<void> recordQuizCompleted(String category, String? productId) =>
      _local.recordQuizCompleted(category, productId);

  @override
  Future<void> recordWhatsappClick(String? productId) =>
      _local.recordWhatsappClick(productId);

  @override
  Future<void> recordFunnelEvent({
    required String eventType,
    required String journeyId,
    required AttributionContext attribution,
    String? productId,
    String? productCode,
  }) async {
    try {
      await _client.rpc(
        'record_pilot_funnel_event',
        params: {
          'payload': {
            'eventType': eventType,
            'journeyId': journeyId,
            'attribution': attribution.toJson(),
            'productId': ?productId,
            'productCode': ?productCode,
          },
        },
      );
    } catch (_) {
      // Funnel analytics must never interrupt the customer journey.
    }
  }

  @override
  Future<void> recordCrossSellShown({
    required String journeyId,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  }) async {
    await _local.recordCrossSellShown(
      journeyId: journeyId,
      primaryProductId: primaryProductId,
      complementaryProductId: complementaryProductId,
      relationId: relationId,
      attribution: attribution,
    );
    await _send(
      eventName: 'cross_sell_shown',
      journeyId: journeyId,
      primaryProductId: primaryProductId,
      complementaryProductId: complementaryProductId,
      relationId: relationId,
      attribution: attribution,
    );
  }

  @override
  Future<void> recordComplementaryChanged({
    required String journeyId,
    required bool added,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  }) async {
    await _local.recordComplementaryChanged(
      journeyId: journeyId,
      added: added,
      primaryProductId: primaryProductId,
      complementaryProductId: complementaryProductId,
      relationId: relationId,
      attribution: attribution,
    );
    await _send(
      eventName: added ? 'complementary_added' : 'complementary_removed',
      journeyId: journeyId,
      primaryProductId: primaryProductId,
      complementaryProductId: complementaryProductId,
      relationId: relationId,
      attribution: attribution,
    );
  }

  Future<void> _send({
    required String eventName,
    required String journeyId,
    required String primaryProductId,
    required String complementaryProductId,
    required String relationId,
    required AttributionContext attribution,
  }) async {
    try {
      await _client.rpc(
        'record_commercial_event',
        params: {
          'payload': {
            'eventName': eventName,
            'journeyId': journeyId,
            'primaryProductId': primaryProductId,
            'complementaryProductId': complementaryProductId,
            'relationId': relationId,
            'attribution': attribution.toJson(),
          },
        },
      );
    } catch (_) {
      // Analytics must never interrupt a recommendation or order request.
    }
  }
}
