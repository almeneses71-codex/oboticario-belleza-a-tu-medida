import '../models/order.dart';

abstract interface class OrderRepository {
  bool get isConfigured;

  Future<CreatedOrder> createOrder(OrderDraft draft);
}

class OrderSubmissionUnavailable implements Exception {
  const OrderSubmissionUnavailable([
    this.message = 'El servicio de pedidos todavía no está configurado.',
  ]);

  final String message;

  @override
  String toString() => message;
}
