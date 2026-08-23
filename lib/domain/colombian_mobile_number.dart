class ColombianMobileNumber {
  const ColombianMobileNumber._();

  static String normalize(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^3\d{9}$').hasMatch(digits)) return '57$digits';
    if (RegExp(r'^573\d{9}$').hasMatch(digits)) return digits;
    return '';
  }

  static bool isValid(String value) => normalize(value).isNotEmpty;
}
