class AttributionContext {
  const AttributionContext({
    required this.channelId,
    required this.source,
    this.sellerId,
    this.campaignId,
  });

  factory AttributionContext.fromUri(Uri uri) {
    final parameters = uri.queryParameters;
    final seller = _firstNonBlank(parameters, const ['vendedor', 'seller']);
    final source =
        _firstNonBlank(parameters, const ['origen', 'utm_source', 'source']) ??
        'directo';
    final channel =
        _firstNonBlank(parameters, const ['canal', 'utm_medium', 'channel']) ??
        source;
    final campaign = _firstNonBlank(parameters, const [
      'campana',
      'utm_campaign',
      'campaign',
    ]);

    return AttributionContext(
      sellerId: seller?.toUpperCase(),
      channelId: channel.toLowerCase(),
      source: source.toLowerCase(),
      campaignId: campaign,
    );
  }

  final String? sellerId;
  final String channelId;
  final String source;
  final String? campaignId;

  bool get hasSeller => sellerId != null;

  Map<String, dynamic> toJson() => {
    'sellerId': sellerId,
    'channelId': channelId,
    'source': source,
    'campaignId': campaignId,
  };

  static String? _firstNonBlank(
    Map<String, String> parameters,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = parameters[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
