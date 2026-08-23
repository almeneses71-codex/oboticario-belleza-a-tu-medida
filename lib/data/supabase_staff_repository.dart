import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/staff_order.dart';
import '../domain/repositories/staff_repository.dart';

class SupabaseStaffRepository implements StaffRepository {
  const SupabaseStaffRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get isConfigured => true;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  Future<StaffProfile> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final profile = await loadCurrentProfile();
    if (profile == null) {
      await _client.auth.signOut();
      throw const AuthException('Este usuario no tiene un perfil autorizado.');
    }
    return profile;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<StaffProfile?> loadCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('staff_profiles')
        .select('role,display_name,seller_id')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return StaffProfile(
      role: StaffRole.values.firstWhere(
        (role) => role.name == row['role'],
        orElse: () => StaffRole.seller,
      ),
      displayName: row['display_name'] as String,
      sellerId: row['seller_id'] as String?,
    );
  }

  @override
  Future<StaffOrderPage> loadOrders({
    StaffOrderFilter filter = const StaffOrderFilter(),
  }) async {
    final matches = await _client.rpc<List<dynamic>>(
      'search_staff_order_ids',
      params: {
        'search_text': filter.search,
        'filter_status': filter.status,
        'filter_seller_name': filter.sellerName,
        'created_after': filter.createdAfter?.toUtc().toIso8601String(),
        'filter_attention': filter.attention,
        'page_offset': filter.offset,
        'page_limit': filter.limit,
      },
    );
    if (matches.isEmpty) {
      return const StaffOrderPage(orders: [], totalCount: 0);
    }
    final ids = matches
        .map((row) => (row as Map<String, dynamic>)['order_id'] as String)
        .toList(growable: false);
    final totalCount =
        (matches.first as Map<String, dynamic>)['total_count'] as int;
    final rows = await _client
        .from('orders')
        .select(
          'id,order_number,status,subtotal_cop,discount_cop,shipping_cop,'
          'shipping_status,created_at,customers(name,whatsapp,city),'
          'order_customer_delivery_preferences(requires_delivery),'
          'origin_seller:sellers!orders_seller_id_fkey(display_name),'
          'assigned_seller:sellers!orders_assigned_seller_id_fkey(id,display_name),'
          'channels(display_name),campaigns(display_name),'
          'order_items(id,product_code,product_name,quantity,item_type,final_unit_price_cop,'
          'order_item_availability_checks(result,note,checker_role,checker_display_name,checked_at)),'
          'order_status_history(previous_status,status,actor_role,actor_display_name,note,created_at),'
          'order_assignment_history(previous_seller_name,new_seller_name,actor_role,actor_display_name,reason,created_at),'
          'order_followups(id,note,due_at,status,creator_role,creator_display_name,created_at,completed_by_name,completed_at,completion_note),'
          'order_contact_events(channel,actor_role,actor_display_name,created_at),'
          'store_purchases(id,status,created_at),'
          'customer_order_acceptances(channel,accepted_total_cop,note,recorder_role,recorder_display_name,accepted_at),'
          'order_delivery_events(previous_shipping_status,previous_shipping_cop,shipping_status,shipping_cop,actor_role,actor_display_name,created_at)',
        )
        .inFilter('id', ids)
        .order('created_at', ascending: false)
        .limit(filter.limit);
    final orders = (rows as List<dynamic>)
        .map((row) => _mapOrder(row as Map<String, dynamic>))
        .toList(growable: false);
    return StaffOrderPage(orders: orders, totalCount: totalCount);
  }

  @override
  Future<Map<String, int>> loadStatusCounts() async {
    final rows = await _client.rpc<List<dynamic>>('staff_order_status_counts');
    return {
      for (final dynamic row in rows)
        (row as Map<String, dynamic>)['status'] as String:
            row['total_count'] as int,
    };
  }

  @override
  Future<Map<String, int>> loadAttentionCounts() async {
    final rows = await _client.rpc<List<dynamic>>('staff_attention_counts');
    return {
      for (final dynamic row in rows)
        (row as Map<String, dynamic>)['attention'] as String:
            row['total_count'] as int,
    };
  }

  @override
  Future<List<StaffSellerOption>> loadAssignableSellers() async {
    final rows = await _client.rpc<List<dynamic>>('list_assignable_sellers');
    return rows
        .map((row) => row as Map<String, dynamic>)
        .map(
          (row) => StaffSellerOption(
            id: row['id'] as String,
            code: row['code'] as String,
            displayName: row['display_name'] as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> assignOrder(
    String orderId,
    String sellerId,
    String reason,
  ) async {
    await _client.rpc<dynamic>(
      'assign_order_responsible',
      params: {
        'target_order_id': orderId,
        'target_seller_id': sellerId,
        'assignment_reason': reason,
      },
    );
  }

  @override
  Future<void> createFollowup(
    String orderId,
    String note,
    DateTime dueAt,
  ) async {
    await _client.rpc<dynamic>(
      'create_order_followup',
      params: {
        'target_order_id': orderId,
        'followup_note': note,
        'followup_due_at': dueAt.toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> completeFollowup(String followupId, String resultNote) async {
    await _client.rpc<dynamic>(
      'complete_order_followup',
      params: {'target_followup_id': followupId, 'result_note': resultNote},
    );
  }

  @override
  Future<void> recordCustomerContact(String orderId) async {
    await _client.rpc<dynamic>(
      'log_order_contact',
      params: {'target_order_id': orderId, 'contact_channel': 'whatsapp'},
    );
  }

  @override
  Future<void> verifyAvailability(
    String orderId,
    Map<String, String> itemResults,
    String? note,
  ) async {
    await _client.rpc<dynamic>(
      'verify_order_availability',
      params: {
        'target_order_id': orderId,
        'item_results': [
          for (final entry in itemResults.entries)
            {'orderItemId': entry.key, 'result': entry.value},
        ],
        'verification_note': note,
      },
    );
  }

  @override
  Future<void> recordCustomerAcceptance(
    String orderId,
    String channel,
    String note,
  ) async {
    await _client.rpc<dynamic>(
      'record_customer_order_acceptance',
      params: {
        'target_order_id': orderId,
        'acceptance_channel': channel,
        'acceptance_note': note,
      },
    );
  }

  @override
  Future<void> updateStatus(
    String orderId,
    String status, {
    String? note,
  }) async {
    await _client.rpc<dynamic>(
      'update_order_status',
      params: {
        'target_order_id': orderId,
        'target_status': status,
        'change_note': note ?? 'Actualizado desde el panel interno.',
      },
    );
  }

  @override
  Future<void> confirmShipping(String orderId, int shippingCop) async {
    await _client.rpc<dynamic>(
      'confirm_order_shipping',
      params: {
        'target_order_id': orderId,
        'confirmed_shipping_cop': shippingCop,
      },
    );
  }

  StaffOrder _mapOrder(Map<String, dynamic> row) {
    final customer = row['customers'] as Map<String, dynamic>? ?? const {};
    final seller = row['origin_seller'] as Map<String, dynamic>?;
    final assignedSeller = row['assigned_seller'] as Map<String, dynamic>?;
    final channel = row['channels'] as Map<String, dynamic>?;
    final campaign = row['campaigns'] as Map<String, dynamic>?;
    final items = (row['order_items'] as List<dynamic>? ?? const [])
        .map((item) => item as Map<String, dynamic>)
        .map((item) {
          final availabilityHistory =
              (item['order_item_availability_checks'] as List<dynamic>? ??
                      const [])
                  .map((check) => check as Map<String, dynamic>)
                  .map(
                    (check) => StaffAvailabilityCheck(
                      result: check['result'] as String,
                      actorName: check['checker_display_name'] as String,
                      actorRole: check['checker_role'] as String,
                      checkedAt: DateTime.parse(check['checked_at'] as String),
                      note: check['note'] as String?,
                    ),
                  )
                  .toList(growable: false)
                ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
          return StaffOrderItem(
            id: item['id'] as String,
            name: item['product_name'] as String,
            code: item['product_code'] as String,
            type: item['item_type'] as String,
            quantity: item['quantity'] as int,
            unitPriceCop: item['final_unit_price_cop'] as int,
            availabilityHistory: availabilityHistory,
          );
        })
        .toList(growable: false);
    final history =
        (row['order_status_history'] as List<dynamic>? ?? const [])
            .map((event) => event as Map<String, dynamic>)
            .map(
              (event) => StaffOrderEvent(
                previousStatus: event['previous_status'] as String?,
                status: event['status'] as String,
                actorRole: event['actor_role'] as String?,
                actorName: event['actor_display_name'] as String?,
                note: event['note'] as String?,
                createdAt: DateTime.parse(
                  event['created_at'] as String,
                ).toLocal(),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final assignmentHistory =
        (row['order_assignment_history'] as List<dynamic>? ?? const [])
            .map((event) => event as Map<String, dynamic>)
            .map(
              (event) => StaffAssignmentEvent(
                previousSellerName: event['previous_seller_name'] as String?,
                newSellerName: event['new_seller_name'] as String,
                actorRole: event['actor_role'] as String?,
                actorName: event['actor_display_name'] as String?,
                reason: event['reason'] as String,
                createdAt: DateTime.parse(event['created_at'] as String),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final followups =
        (row['order_followups'] as List<dynamic>? ?? const [])
            .map((event) => event as Map<String, dynamic>)
            .map(
              (event) => StaffFollowup(
                id: event['id'] as String,
                note: event['note'] as String,
                dueAt: DateTime.parse(event['due_at'] as String),
                status: event['status'] as String,
                creatorName: event['creator_display_name'] as String?,
                creatorRole: event['creator_role'] as String?,
                createdAt: DateTime.parse(event['created_at'] as String),
                completedByName: event['completed_by_name'] as String?,
                completedAt: event['completed_at'] == null
                    ? null
                    : DateTime.parse(event['completed_at'] as String),
                completionNote: event['completion_note'] as String?,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.dueAt.compareTo(a.dueAt));
    final contactHistory =
        (row['order_contact_events'] as List<dynamic>? ?? const [])
            .map((event) => event as Map<String, dynamic>)
            .map(
              (event) => StaffContactEvent(
                channel: event['channel'] as String,
                actorRole: event['actor_role'] as String,
                actorName: event['actor_display_name'] as String,
                createdAt: DateTime.parse(event['created_at'] as String),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final purchaseData = row['store_purchases'];
    final purchaseRow = switch (purchaseData) {
      Map<String, dynamic> value => value,
      List<dynamic> value when value.isNotEmpty =>
        value.first as Map<String, dynamic>,
      _ => null,
    };
    final storePurchase = purchaseRow == null
        ? null
        : StaffStorePurchase(
            id: purchaseRow['id'] as String,
            status: purchaseRow['status'] as String,
            createdAt: DateTime.parse(purchaseRow['created_at'] as String),
          );
    final customerAcceptances =
        (row['customer_order_acceptances'] as List<dynamic>? ?? const [])
            .map((event) => event as Map<String, dynamic>)
            .map(
              (event) => StaffCustomerAcceptance(
                channel: event['channel'] as String,
                acceptedTotalCop: event['accepted_total_cop'] as int,
                note: event['note'] as String,
                actorName: event['recorder_display_name'] as String,
                actorRole: event['recorder_role'] as String,
                acceptedAt: DateTime.parse(event['accepted_at'] as String),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.acceptedAt.compareTo(a.acceptedAt));
    final deliveryHistory =
        (row['order_delivery_events'] as List<dynamic>? ?? const [])
            .map((event) => event as Map<String, dynamic>)
            .map(
              (event) => StaffDeliveryEvent(
                previousStatus: event['previous_shipping_status'] as String,
                previousCop: event['previous_shipping_cop'] as int,
                status: event['shipping_status'] as String,
                shippingCop: event['shipping_cop'] as int,
                actorName: event['actor_display_name'] as String,
                actorRole: event['actor_role'] as String,
                createdAt: DateTime.parse(event['created_at'] as String),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final preferenceData = row['order_customer_delivery_preferences'];
    final preferenceRow = switch (preferenceData) {
      Map<String, dynamic> value => value,
      List<dynamic> value when value.isNotEmpty =>
        value.first as Map<String, dynamic>,
      _ => null,
    };
    return StaffOrder(
      id: row['id'] as String,
      number: row['order_number'] as String,
      status: row['status'] as String,
      customerName: customer['name'] as String? ?? 'Sin nombre',
      customerWhatsapp: customer['whatsapp'] as String? ?? '',
      customerCity: customer['city'] as String?,
      customerRequiresDelivery: preferenceRow?['requires_delivery'] as bool?,
      sellerName: seller?['display_name'] as String?,
      assignedSellerId: assignedSeller?['id'] as String?,
      assignedSellerName: assignedSeller?['display_name'] as String?,
      channelName: channel?['display_name'] as String?,
      campaignName: campaign?['display_name'] as String?,
      items: items,
      history: history,
      assignmentHistory: assignmentHistory,
      followups: followups,
      contactHistory: contactHistory,
      storePurchase: storePurchase,
      customerAcceptances: customerAcceptances,
      deliveryHistory: deliveryHistory,
      subtotalCop: row['subtotal_cop'] as int,
      discountCop: row['discount_cop'] as int,
      shippingCop: row['shipping_cop'] as int,
      shippingStatus: row['shipping_status'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}
