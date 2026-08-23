import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/order.dart';
import '../domain/repositories/order_repository.dart';

class SupabaseOrderRepository implements OrderRepository {
  const SupabaseOrderRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get isConfigured => true;

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
