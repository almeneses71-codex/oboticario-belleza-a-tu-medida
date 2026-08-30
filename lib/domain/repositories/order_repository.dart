import '../models/order.dart';
import '../models/customer_draft.dart';

abstract interface class OrderRepository {
  bool get isConfigured;

  Future<CreatedOrder> createOrder(OrderDraft draft);
}

abstract interface class WheelRepository {
  Future<WheelCampaignStatus> loadWheelCampaignStatus();


  Future<WheelBenefit> spinWheel({
    required String journeyId,
    required CustomerDraft customer,
    required List<OrderItemDraft> items,
  });
}

abstract interface class ProductAvailabilityRepository {
  Future<Set<String>> loadPurchasableProductIds();
}

class OrderSubmissionUnavailable implements Exception {
  const OrderSubmissionUnavailable([
    this.message = 'El servicio de pedidos todavía no está configurado.',
  ]);

  final String message;

  @override
  String toString() => message;
}
