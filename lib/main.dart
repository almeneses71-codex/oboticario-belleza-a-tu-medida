import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/app_config.dart';
import 'data/local_catalog_repository.dart';
import 'data/local_cross_sell_repository.dart';
import 'data/supabase_order_repository.dart';
import 'data/supabase_staff_repository.dart';
import 'domain/repositories/order_repository.dart';
import 'domain/repositories/staff_repository.dart';
import 'services/analytics_service.dart';
import 'services/local_analytics_service.dart';
import 'services/supabase_analytics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OrderRepository? orderRepository;
  StaffRepository? staffRepository;
  final localAnalytics = LocalAnalyticsService();
  AnalyticsService analytics = localAnalytics;
  debugPrint('[config-diagnostic] configured=${AppConfig.supabaseConfigured} url=${AppConfig.supabaseUrl} keyLength=${AppConfig.supabaseAnonKey.length}');
  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    final client = Supabase.instance.client;
    orderRepository = SupabaseOrderRepository(client);
    staffRepository = SupabaseStaffRepository(client);
    debugPrint('[staff-diagnostic] staffRepository creado correctamente');
    analytics = SupabaseAnalyticsService(client, localAnalytics);
  }
  runApp(
    BeautyAdvisorApp(
      repository: const LocalCatalogRepository(),
      crossSellRepository: const LocalCrossSellRepository(),
      orderRepository: orderRepository,
      staffRepository: staffRepository,
      analytics: analytics,
    ),
  );
}
