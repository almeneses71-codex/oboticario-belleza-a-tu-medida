import 'attribution_context.dart';
import 'customer_draft.dart';

enum OrderStatus {
  requested,
  contacted,
  availabilityVerified,
  confirmed,
  pendingPayment,
  paymentUnderReview,
  paid,
  preparing,
  shipped,
  delivered,
  cancelled,
  returned,
  refunded,
}

enum ShippingStatus {
  pendingQuote,
  manuallyConfirmed,
  promotional,
  notRequired,
}

enum OrderItemType { primary, complementary, kit, other }

enum DeliveryMethod { homeDelivery, advisorArrangement }

class DeliveryDetails {
  const DeliveryDetails({
    required this.city,
    required this.address,
    required this.neighborhood,
    required this.recipientName,
    this.directions,
  });

  final String city;
  final String address;
  final String neighborhood;
  final String recipientName;
  final String? directions;

  bool get isValid =>
      city.trim().isNotEmpty &&
      address.trim().isNotEmpty &&
      neighborhood.trim().isNotEmpty &&
      recipientName.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'city': city.trim(),
    'address': address.trim(),
    'neighborhood': neighborhood.trim(),
    'recipientName': recipientName.trim(),
    'directions': directions?.trim(),
  };
}

class OrderItemDraft {
  const OrderItemDraft({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.itemType,
    required this.quantity,
    required this.originalUnitPriceCop,
    this.discountCop = 0,
    this.crossSellRelationId,
  });

  final String productId;
  final String productCode;
  final String productName;
  final OrderItemType itemType;
  final int quantity;
  final int originalUnitPriceCop;
  final int discountCop;
  final String? crossSellRelationId;

  int get finalUnitPriceCop => originalUnitPriceCop - discountCop;
  int get subtotalCop => quantity * finalUnitPriceCop;
  bool get hasValidPrice =>
      originalUnitPriceCop >= 0 &&
      discountCop >= 0 &&
      discountCop <= originalUnitPriceCop;
  bool get isValidForCurrentPhase =>
      hasValidPrice &&
      discountCop == 0 &&
      itemType != OrderItemType.kit &&
      (itemType == OrderItemType.complementary
          ? crossSellRelationId?.trim().isNotEmpty == true
          : crossSellRelationId == null);

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productCode': productCode,
    'productName': productName,
    'itemType': itemType.name,
    'quantity': quantity,
    'originalUnitPriceCop': originalUnitPriceCop,
    'discountCop': discountCop,
    'finalUnitPriceCop': finalUnitPriceCop,
    'subtotalCop': subtotalCop,
    'crossSellRelationId': crossSellRelationId,
  };
}

class OrderAmounts {
  const OrderAmounts({
    required this.subtotalCop,
    this.discountCop = 0,
    this.shippingCop = 0,
  }) : assert(subtotalCop >= 0),
       assert(discountCop >= 0),
       assert(shippingCop >= 0),
       assert(discountCop <= subtotalCop);

  factory OrderAmounts.fromItems(
    Iterable<OrderItemDraft> items, {
    int discountCop = 0,
    int shippingCop = 0,
  }) => OrderAmounts(
    subtotalCop: items.fold(0, (total, item) => total + item.subtotalCop),
    discountCop: discountCop,
    shippingCop: shippingCop,
  );

  final int subtotalCop;
  final int discountCop;
  final int shippingCop;

  int get totalCop => subtotalCop - discountCop + shippingCop;

  Map<String, dynamic> toJson() => {
    'subtotalCop': subtotalCop,
    'discountCop': discountCop,
    'shippingCop': shippingCop,
    'totalCop': totalCop,
  };
}

class OrderDraft {
  const OrderDraft({
    required this.journeyId,
    required this.customer,
    required this.attribution,
    required this.items,
    required this.amounts,
    required this.shippingStatus,
    required this.requiresDelivery,
    this.deliveryDetails,
    this.shippingEstimateMinCop = 10000,
    this.shippingEstimateMaxCop = 15000,
    this.status = OrderStatus.requested,
  });

  final CustomerDraft customer;
  final String journeyId;
  final AttributionContext attribution;
  final List<OrderItemDraft> items;
  final OrderAmounts amounts;
  final ShippingStatus shippingStatus;
  final bool requiresDelivery;
  final DeliveryDetails? deliveryDetails;
  final int shippingEstimateMinCop;
  final int shippingEstimateMaxCop;
  final OrderStatus status;

  bool get isValid =>
      RegExp(r'^[a-f0-9]{32}$').hasMatch(journeyId) &&
      customer.isValid &&
      items.where((item) => item.itemType == OrderItemType.primary).length ==
          1 &&
      items
              .where((item) => item.itemType == OrderItemType.complementary)
              .length <=
          2 &&
      items.where((item) => item.itemType == OrderItemType.other).length <= 3 &&
      items.every((item) => item.isValidForCurrentPhase) &&
      (requiresDelivery
          ? deliveryDetails?.isValid == true
          : deliveryDetails == null) &&
      shippingEstimateMinCop >= 0 &&
      shippingEstimateMaxCop >= shippingEstimateMinCop;

  Map<String, dynamic> toJson() => {
    'journeyId': journeyId,
    'customer': customer.toJson(),
    'attribution': attribution.toJson(),
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'amounts': amounts.toJson(),
    'shippingStatus': shippingStatus.name,
    'requiresDelivery': requiresDelivery,
    'deliveryMethod': requiresDelivery
        ? DeliveryMethod.homeDelivery.name
        : DeliveryMethod.advisorArrangement.name,
    'deliveryDetails': deliveryDetails?.toJson(),
    'shippingEstimateMinCop': shippingEstimateMinCop,
    'shippingEstimateMaxCop': shippingEstimateMaxCop,
    'status': status.name,
  };
}

class CreatedOrder {
  const CreatedOrder({
    required this.id,
    required this.number,
    required this.status,
  });

  final String id;
  final String number;
  final OrderStatus status;
}

class WheelCampaignStatus {
  const WheelCampaignStatus({required this.active});

  final bool active;
}

class WheelBenefit {
  const WheelBenefit({
    required this.spinId,
    required this.discountPercent,
    required this.productsCop,
    required this.discountCop,
    required this.netProductsCop,
  });

  final String spinId;
  final int discountPercent;
  final int productsCop;
  final int discountCop;
  final int netProductsCop;
}
