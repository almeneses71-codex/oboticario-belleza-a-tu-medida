import 'package:url_launcher/url_launcher.dart';

import '../app/app_config.dart';
import '../domain/models/product.dart';

class WhatsAppLinkService {
  const WhatsAppLinkService();

  Uri? buildProductUri({
    required Product product,
    required Iterable<String> answerLabels,
  }) {
    if (!AppConfig.whatsappConfigured) return null;
    final price = _formatCop(product.priceCop);
    final message =
        'Hola, ${AppConfig.advisorName}. Vi mi recomendación en oBoticario '
        'Belleza a tu Medida. '
        'Me interesó ${product.name} (${product.presentation}), código '
        '${product.code}. Precio de referencia del ciclo 08: $price. '
        'Busco ${answerLabels.join(', ')}. ¿Puedes confirmarme disponibilidad '
        'y precio vigente?';
    return Uri.https(
      'wa.me',
      '/${AppConfig.whatsappNumber}',
      {'text': message},
    );
  }

  Uri? buildAdvisorUri() {
    if (!AppConfig.whatsappConfigured) return null;
    return Uri.https(
      'wa.me',
      '/${AppConfig.whatsappNumber}',
      {
        'text': 'Hola, ${AppConfig.advisorName}. Vi oBoticario Belleza a tu '
            'Medida y quiero recibir asesoría personal para elegir un producto.',
      },
    );
  }

  Future<bool> launch(Uri? uri) async {
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatCop(int value) {
    final digits = value.toString();
    final buffer = StringBuffer(r'$');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}
