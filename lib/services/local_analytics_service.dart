import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

class LocalAnalyticsService implements AnalyticsService {
  static const _opens = 'metric_app_opens';
  static const _completed = 'metric_quiz_completed';
  static const _whatsapp = 'metric_whatsapp_clicks';

  @override
  Future<Map<String, int>> getCounters() async {
    final preferences = await SharedPreferences.getInstance();
    return {
      'app_opens': preferences.getInt(_opens) ?? 0,
      'quiz_completed': preferences.getInt(_completed) ?? 0,
      'whatsapp_clicks': preferences.getInt(_whatsapp) ?? 0,
    };
  }

  @override
  Future<void> recordAppOpen() => _increment(_opens);

  @override
  Future<void> recordQuizCompleted(String category, String? productId) =>
      _increment(_completed);

  @override
  Future<void> recordWhatsappClick(String? productId) => _increment(_whatsapp);

  Future<void> _increment(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(key, (preferences.getInt(key) ?? 0) + 1);
  }
}

