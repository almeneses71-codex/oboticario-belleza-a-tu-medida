import '../models/staff_order.dart';

class StaffOrderFilter {
  const StaffOrderFilter({
    this.search = '',
    this.status,
    this.sellerName,
    this.createdAfter,
    this.attention,
    this.offset = 0,
    this.limit = 25,
  });

  final String search;
  final String? status;
  final String? sellerName;
  final DateTime? createdAfter;
  final String? attention;
  final int offset;
  final int limit;

  StaffOrderFilter copyWith({int? offset, int? limit}) => StaffOrderFilter(
    search: search,
    status: status,
    sellerName: sellerName,
    createdAfter: createdAfter,
    attention: attention,
    offset: offset ?? this.offset,
    limit: limit ?? this.limit,
  );
}

class StaffOrderPage {
  const StaffOrderPage({required this.orders, required this.totalCount});
  final List<StaffOrder> orders;
  final int totalCount;
}

abstract interface class StaffRepository {
  bool get isConfigured;
  bool get hasSession;

  Future<StaffProfile> signIn({
    required String email,
    required String password,
  });
  Future<void> signOut();
  Future<StaffProfile?> loadCurrentProfile();
  Future<StaffOrderPage> loadOrders({StaffOrderFilter filter});
  Future<Map<String, int>> loadStatusCounts();
  Future<Map<String, int>> loadAttentionCounts();
  Future<List<StaffSellerOption>> loadAssignableSellers();
  Future<void> assignOrder(String orderId, String sellerId, String reason);
  Future<void> createFollowup(String orderId, String note, DateTime dueAt);
  Future<void> completeFollowup(String followupId, String resultNote);
  Future<void> recordCustomerContact(String orderId);
  Future<void> verifyAvailability(
    String orderId,
    Map<String, String> itemResults,
    String? note,
  );
  Future<void> recordCustomerAcceptance(
    String orderId,
    String channel,
    String note,
  );
  Future<void> updateStatus(String orderId, String status, {String? note});
  Future<void> confirmShipping(String orderId, int shippingCop);
}
