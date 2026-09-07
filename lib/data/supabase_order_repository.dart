import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/order.dart';
import '../domain/models/customer_draft.dart';
import '../domain/repositories/order_repository.dart';

class SupabaseOrderRepository
    implements
        OrderRepository,
        WheelRepository,
        ProductAvailabilityRepository,
        ImmediateStockRepository {
  const SupabaseOrderRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> loadPurchasableProductIds() async {
    final response = await _client
        .from('products')
        .select('id')
        .eq('active', true)
        .eq('available', true)
        .eq('eligible', true)
        .eq('is_suggested_kit', false);

    return response.map((row) => row['id'] as String).toSet();
  }

  @override
  Future<Set<String>> loadImmediateStockCodes(Set<String> codes) async {
    if (codes.isEmpty) return const {};
    final response = await _client.rpc<List<dynamic>>(
      'get_immediate_stock',
      params: {'requested_codes': codes.toList(growable: false)},
    );
    final rows = response.cast<Map<String, dynamic>>();
    final returnedCodes = rows.map((row) => row['code'] as String).toSet();
    if (rows.length != codes.length ||
        returnedCodes.length != codes.length ||
        !returnedCodes.containsAll(codes)) {
      throw const FormatException('Respuesta incompleta de inventario físico.');
    }
    return rows
        .where((row) => row['has_immediate_stock'] == true)
        .map((row) => row['code'] as String)
        .toSet();
  }

  @override
  Future<WheelCampaignStatus> loadWheelCampaignStatus() async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'get_amor_amistad_2026_status',
    );

    return WheelCampaignStatus(active: response['active'] as bool? ?? false);
  }

  @override
  Future<WheelBenefit> spinWheel({
    required String journeyId,
    required CustomerDraft customer,
    required List<OrderItemDraft> items,
  }) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'spin_amor_amistad_2026',
      params: {
        'payload': {
          'journeyId': journeyId,
          'customer': customer.toJson(),
          'items': items.map((item) => item.toJson()).toList(growable: false),
        },
      },
    );

    return WheelBenefit(
      spinId: response['spin_id'] as String,
      discountPercent: (response['discount_percent'] as num).toInt(),
      productsCop: (response['products_cop'] as num).toInt(),
      discountCop: (response['discount_cop'] as num).toInt(),
      netProductsCop: (response['net_products_cop'] as num).toInt(),
    );
  }

  @override
  Future<CreatedOrder> createOrder(OrderDraft draft) async {
    if (!draft.isValid) {
      throw const FormatException('La solicitud de pedido está incompleta.');
    }

    final response = await _client.rpc<Map<String, dynamic>>(
      'create_order_request_with_delivery',
      params: {'payload': draft.toJson()},
    );

    return CreatedOrder(
      id: response['order_id'] as String,
      number: response['order_number'] as String,
      status: OrderStatus.requested,
    );
  }
}
