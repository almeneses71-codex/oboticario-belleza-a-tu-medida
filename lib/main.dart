import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/local_catalog_repository.dart';
import 'services/local_analytics_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    BeautyAdvisorApp(
      repository: const LocalCatalogRepository(),
      analytics: LocalAnalyticsService(),
    ),
  );
}

