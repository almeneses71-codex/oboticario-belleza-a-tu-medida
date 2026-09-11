import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oboticario_belleza_a_tu_medida/app/staff_auth_restore.dart';

void main() {
  test('uses current session when auth event occurred before listener', () async {
    final authEvents = StreamController<String?>.broadcast();
    addTearDown(authEvents.close);

    authEvents.add('ana-session');
    final session = await waitForCurrentOrAuthEvent<String>(
      currentValue: () => 'ana-session',
      events: authEvents.stream,
      timeout: const Duration(milliseconds: 50),
    );

    expect(session, 'ana-session');
  });

  test('returns safely when Supabase does not emit another event', () async {
    final authEvents = StreamController<String?>.broadcast();
    addTearDown(authEvents.close);

    final session = await waitForCurrentOrAuthEvent<String>(
      currentValue: () => null,
      events: authEvents.stream,
      timeout: const Duration(milliseconds: 20),
    );

    expect(session, isNull);
  });
}
