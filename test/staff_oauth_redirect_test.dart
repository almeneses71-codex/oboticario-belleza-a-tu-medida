import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/data/supabase_staff_repository.dart';

void main() {
  test('Google OAuth uses web URL on web and custom scheme on native', () {
    final webRedirect = resolveStaffOAuthRedirect(
      web: true,
      currentUri: Uri.parse(
        'https://oboticario.vercel.app/admin?source=google',
      ),
    );
    final nativeRedirect = resolveStaffOAuthRedirect(
      web: false,
      currentUri: Uri.parse('https://oboticario.vercel.app/'),
    );

    expect(webRedirect, 'https://oboticario.vercel.app/');
    expect(nativeRedirect, staffNativeOAuthCallback);
  });
}
