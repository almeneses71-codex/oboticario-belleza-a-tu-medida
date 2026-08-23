import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/app_config.dart';
import 'data/local_catalog_repository.dart';
import 'data/local_cross_sell_repository.dart';
import 'data/supabase_order_repository.dart';
import 'domain/repositories/order_repository.dart';
import 'services/local_analytics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OrderRepository? orderRepository;
  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    orderRepository = SupabaseOrderRepository(Supabase.instance.client);
  }
  runApp(
    BeautyAdvisorApp(
      repository: const LocalCatalogRepository(),
      crossSellRepository: const LocalCrossSellRepository(),
      orderRepository: orderRepository,
      analytics: LocalAnalyticsService(),
    ),
  );
}
