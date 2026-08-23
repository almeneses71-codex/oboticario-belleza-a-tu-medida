abstract interface class AnalyticsService {
  Future<void> recordAppOpen();
  Future<void> recordQuizCompleted(String category, String? productId);
  Future<void> recordWhatsappClick(String? productId);
  Future<Map<String, int>> getCounters();
}

