class AppConfig {
  const AppConfig._();

  static const catalogCycle = '08-2026';
  static final priceValidUntil = DateTime(2026, 8, 31, 23, 59, 59);
  static const whatsappNumber = String.fromEnvironment(
    'WHATSAPP_NUMBER',
    defaultValue: '',
  );
  static const advisorName = String.fromEnvironment(
    'ADVISOR_NAME',
    defaultValue: 'Dario y Ana',
  );
  static const independentAdvisorNotice =
      'Asesor independiente de productos O Boticário. No es una aplicación '
      'oficial de la marca. Las recomendaciones son orientativas y se basan '
      'en tus respuestas y en el catálogo disponible. Confirma precio y '
      'disponibilidad antes de comprar. No sustituye asesoría médica o '
      'dermatológica.';

  static bool get whatsappConfigured =>
      RegExp(r'^\d{8,15}$').hasMatch(whatsappNumber);

  static bool get priceIsCurrent => DateTime.now().isBefore(priceValidUntil);
}

