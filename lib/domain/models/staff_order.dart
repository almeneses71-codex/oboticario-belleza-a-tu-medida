enum StaffRole { admin, owner, manager, seller }

enum StaffOrderNextAction {
  markContacted,
  verifyAvailability,
  markAvailabilityVerified,
  confirmShipping,
  recordCustomerAcceptance,
  confirmOrder,
  none,
}

class StaffSellerOption {
  const StaffSellerOption({
    required this.id,
    required this.code,
    required this.displayName,
  });
  final String id;
  final String code;
  final String displayName;
}

class StaffOrderItem {
  const StaffOrderItem({
    required this.id,
    required this.name,
    required this.code,
    required this.type,
    required this.quantity,
    required this.unitPriceCop,
    this.availabilityHistory = const [],
  });
  final String id;
  final String name;
  final String code;
  final String type;
  final int quantity;
  final int unitPriceCop;
  final List<StaffAvailabilityCheck> availabilityHistory;
  int get subtotalCop => quantity * unitPriceCop;
  StaffAvailabilityCheck? get latestAvailability =>
      availabilityHistory.isEmpty ? null : availabilityHistory.first;
  bool get hasAvailabilityIssue =>
      latestAvailability != null && latestAvailability!.result != 'available';
}

class StaffAvailabilityCheck {
  const StaffAvailabilityCheck({
    required this.result,
    required this.actorName,
    required this.actorRole,
    required this.checkedAt,
    this.note,
  });

  final String result;
  final String actorName;
  final String actorRole;
  final DateTime checkedAt;
  final String? note;
}

class StaffOrderEvent {
  const StaffOrderEvent({
    required this.status,
    required this.createdAt,
    this.previousStatus,
    this.actorName,
    this.actorRole,
    this.note,
  });
  final String? previousStatus;
  final String status;
  final DateTime createdAt;
  final String? actorName;
  final String? actorRole;
  final String? note;
}

class StaffAssignmentEvent {
  const StaffAssignmentEvent({
    required this.newSellerName,
    required this.createdAt,
    required this.reason,
    this.previousSellerName,
    this.actorName,
    this.actorRole,
  });
  final String? previousSellerName;
  final String newSellerName;
  final DateTime createdAt;
  final String? actorName;
  final String? actorRole;
  final String reason;
}

class StaffFollowup {
  const StaffFollowup({
    required this.id,
    required this.note,
    required this.dueAt,
    required this.status,
    required this.createdAt,
    this.creatorName,
    this.creatorRole,
    this.completedByName,
    this.completedAt,
    this.completionNote,
  });
  final String id;
  final String note;
  final DateTime dueAt;
  final String status;
  final DateTime createdAt;
  final String? creatorName;
  final String? creatorRole;
  final String? completedByName;
  final DateTime? completedAt;
  final String? completionNote;

  bool get isOpen => status == 'open';
  bool get isOverdue => isOpen && dueAt.isBefore(DateTime.now());
}

class StaffContactEvent {
  const StaffContactEvent({
    required this.channel,
    required this.actorName,
    required this.actorRole,
    required this.createdAt,
  });

  final String channel;
  final String actorName;
  final String actorRole;
  final DateTime createdAt;
}

class StaffStorePurchase {
  const StaffStorePurchase({
    required this.id,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String status;
  final DateTime createdAt;
}

class StaffCustomerAcceptance {
  const StaffCustomerAcceptance({
    required this.channel,
    required this.acceptedTotalCop,
    required this.note,
    required this.actorName,
    required this.actorRole,
    required this.acceptedAt,
  });

  final String channel;
  final int acceptedTotalCop;
  final String note;
  final String actorName;
  final String actorRole;
  final DateTime acceptedAt;
}

class StaffDeliveryEvent {
  const StaffDeliveryEvent({
    required this.previousStatus,
    required this.previousCop,
    required this.status,
    required this.shippingCop,
    required this.actorName,
    required this.actorRole,
    required this.createdAt,
  });

  final String previousStatus;
  final int previousCop;
  final String status;
  final int shippingCop;
  final String actorName;
  final String actorRole;
  final DateTime createdAt;
}

class StaffProfile {
  const StaffProfile({
    required this.role,
    required this.displayName,
    this.sellerId,
  });

  final StaffRole role;
  final String displayName;
  final String? sellerId;

  bool get isAdmin => role == StaffRole.admin;
  bool get canViewAll => const {
    StaffRole.admin,
    StaffRole.owner,
    StaffRole.manager,
  }.contains(role);
}

class StaffOrder {
  const StaffOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.customerName,
    required this.customerWhatsapp,
    required this.subtotalCop,
    required this.discountCop,
    required this.shippingCop,
    required this.shippingStatus,
    required this.createdAt,
    this.customerCity,
    this.customerRequiresDelivery,
    this.sellerName,
    this.assignedSellerId,
    this.assignedSellerName,
    this.channelName,
    this.campaignName,
    this.items = const [],
    this.history = const [],
    this.assignmentHistory = const [],
    this.followups = const [],
    this.contactHistory = const [],
    this.storePurchase,
    this.customerAcceptances = const [],
    this.deliveryHistory = const [],
  });

  final String id;
  final String number;
  final String status;
  final String customerName;
  final String customerWhatsapp;
  final String? customerCity;
  final bool? customerRequiresDelivery;
  final String? sellerName;
  final String? assignedSellerId;
  final String? assignedSellerName;
  final String? channelName;
  final String? campaignName;
  final List<StaffOrderItem> items;
  final List<StaffOrderEvent> history;
  final List<StaffAssignmentEvent> assignmentHistory;
  final List<StaffFollowup> followups;
  final List<StaffContactEvent> contactHistory;
  final StaffStorePurchase? storePurchase;
  final List<StaffCustomerAcceptance> customerAcceptances;
  final List<StaffDeliveryEvent> deliveryHistory;
  final int subtotalCop;
  final int discountCop;
  final int shippingCop;
  final String shippingStatus;
  final DateTime createdAt;

  int get totalCop => subtotalCop - discountCop + shippingCop;
  bool get shippingConfirmed => shippingStatus != 'pending_quote';
  bool get hasAvailabilityIssue =>
      items.any((item) => item.hasAvailabilityIssue);
  bool get hasCompleteAvailability =>
      items.isNotEmpty &&
      items.every((item) => item.latestAvailability != null);
  bool get hasCurrentCustomerAcceptance => customerAcceptances.any(
    (acceptance) => acceptance.acceptedTotalCop == totalCop,
  );
  bool get needsCustomerAcceptance =>
      status == 'availability_verified' &&
      shippingConfirmed &&
      !hasCurrentCustomerAcceptance;
  bool get isClosed =>
      const {'cancelled', 'returned', 'refunded'}.contains(status);
  StaffOrderEvent? get closingEvent {
    StaffOrderEvent? result;
    for (final event in history) {
      if (const {'cancelled', 'returned', 'refunded'}.contains(event.status) &&
          (result == null || event.createdAt.isAfter(result.createdAt))) {
        result = event;
      }
    }
    return result;
  }

  bool get isConfirmed => const {
    'confirmed',
    'pending_payment',
    'payment_under_review',
    'paid',
    'delivered',
  }.contains(status);
  int get completedCommercialSteps {
    if (isClosed) return 0;
    if (isConfirmed) return 5;
    var completed = 0;
    if (status != 'requested') completed++;
    if (!const {'requested', 'contacted'}.contains(status) ||
        (hasCompleteAvailability && !hasAvailabilityIssue)) {
      completed++;
    }
    if (shippingConfirmed) completed++;
    if (hasCurrentCustomerAcceptance) completed++;
    return completed.clamp(0, 5);
  }

  double get commercialProgress => completedCommercialSteps / 5;
  bool get canCancel => const {
    'requested',
    'contacted',
    'availability_verified',
    'confirmed',
    'pending_payment',
    'payment_under_review',
  }.contains(status);

  String? get nextStatus => switch (status) {
    'requested' => 'contacted',
    'contacted' => 'availability_verified',
    'availability_verified'
        when shippingConfirmed && hasCurrentCustomerAcceptance =>
      'confirmed',
    _ => null,
  };

  StaffOrderNextAction get nextAction => switch (status) {
    'requested' => StaffOrderNextAction.markContacted,
    'contacted' when !hasCompleteAvailability || hasAvailabilityIssue =>
      StaffOrderNextAction.verifyAvailability,
    'contacted' => StaffOrderNextAction.markAvailabilityVerified,
    'availability_verified' when !shippingConfirmed =>
      StaffOrderNextAction.confirmShipping,
    'availability_verified' when !hasCurrentCustomerAcceptance =>
      StaffOrderNextAction.recordCustomerAcceptance,
    'availability_verified' => StaffOrderNextAction.confirmOrder,
    _ => StaffOrderNextAction.none,
  };
}
