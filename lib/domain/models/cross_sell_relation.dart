enum CrossSellRelationType {
  sameLine,
  routineStep,
  sameNeed,
  compatibleCare,
  giftUpgrade,
}

class CrossSellRelation {
  const CrossSellRelation({
    required this.id,
    required this.sourceProductId,
    required this.complementaryProductId,
    required this.type,
    required this.priority,
    required this.benefit,
    required this.reason,
    this.active = true,
    this.startsAt,
    this.endsAt,
    this.campaignId,
  }) : assert(priority >= 1 && priority <= 5);

  factory CrossSellRelation.fromJson(Map<String, dynamic> json) =>
      CrossSellRelation(
        id: json['id'] as String,
        sourceProductId: json['sourceProductId'] as String,
        complementaryProductId: json['complementaryProductId'] as String,
        type: CrossSellRelationType.values.byName(json['type'] as String),
        priority: (json['priority'] as num).toInt(),
        benefit: json['benefit'] as String,
        reason: json['reason'] as String,
        active: json['active'] as bool? ?? true,
        startsAt: _date(json['startsAt']),
        endsAt: _date(json['endsAt']),
        campaignId: json['campaignId'] as String?,
      );

  final String id;
  final String sourceProductId;
  final String complementaryProductId;
  final CrossSellRelationType type;
  final int priority;
  final String benefit;
  final String reason;
  final bool active;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? campaignId;

  bool isActiveAt(DateTime instant) =>
      active &&
      (startsAt == null || !instant.isBefore(startsAt!)) &&
      (endsAt == null || !instant.isAfter(endsAt!));
}

DateTime? _date(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.parse(value) : null;
