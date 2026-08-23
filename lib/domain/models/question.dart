class Question {
  const Question({
    required this.id,
    required this.category,
    required this.order,
    required this.text,
    required this.options,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        category: json['category'] as String,
        order: (json['order'] as num).toInt(),
        text: json['text'] as String,
        options: (json['options'] as List<dynamic>)
            .map((item) => AnswerOption.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final String id;
  final String category;
  final int order;
  final String text;
  final List<AnswerOption> options;
}

class AnswerOption {
  const AnswerOption({
    required this.id,
    required this.label,
    required this.reason,
    required this.hardFilters,
    required this.boosts,
    this.targetIntensity,
  });

  factory AnswerOption.fromJson(Map<String, dynamic> json) => AnswerOption(
        id: json['id'] as String,
        label: json['label'] as String,
        reason: json['reason'] as String? ?? '',
        hardFilters: Map<String, dynamic>.from(
          json['hardFilters'] as Map<String, dynamic>? ?? const {},
        ),
        boosts: (json['boosts'] as List<dynamic>? ?? const [])
            .map((item) => BoostRule.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        targetIntensity: (json['targetIntensity'] as num?)?.toInt(),
      );

  final String id;
  final String label;
  final String reason;
  final Map<String, dynamic> hardFilters;
  final List<BoostRule> boosts;
  final int? targetIntensity;
}

class BoostRule {
  const BoostRule({required this.queries, required this.points});

  factory BoostRule.fromJson(Map<String, dynamic> json) => BoostRule(
        queries: (json['queries'] as List<dynamic>).cast<String>(),
        points: (json['points'] as num).toInt(),
      );

  final List<String> queries;
  final int points;
}

