import 'models/order.dart';

class OrderStatusTransitions {
  const OrderStatusTransitions._();

  static const Map<OrderStatus, Set<OrderStatus>> allowed = {
    OrderStatus.requested: {OrderStatus.contacted, OrderStatus.cancelled},
    OrderStatus.contacted: {
      OrderStatus.availabilityVerified,
      OrderStatus.cancelled,
    },
    OrderStatus.availabilityVerified: {
      OrderStatus.confirmed,
      OrderStatus.cancelled,
    },
    OrderStatus.confirmed: {OrderStatus.pendingPayment, OrderStatus.cancelled},
    OrderStatus.pendingPayment: {
      OrderStatus.paymentUnderReview,
      OrderStatus.cancelled,
    },
    OrderStatus.paymentUnderReview: {OrderStatus.paid, OrderStatus.cancelled},
    OrderStatus.paid: {OrderStatus.preparing, OrderStatus.refunded},
    OrderStatus.preparing: {OrderStatus.shipped, OrderStatus.refunded},
    OrderStatus.shipped: {OrderStatus.delivered, OrderStatus.returned},
    OrderStatus.delivered: {OrderStatus.returned},
    OrderStatus.returned: {OrderStatus.refunded},
    OrderStatus.cancelled: {},
    OrderStatus.refunded: {},
  };

  static bool canTransition(OrderStatus current, OrderStatus next) =>
      allowed[current]?.contains(next) ?? false;
}
