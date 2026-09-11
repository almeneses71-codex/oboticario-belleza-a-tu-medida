import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

Future<T?> waitForCurrentOrAuthEvent<T extends Object>({
  required T? Function() currentValue,
  required Stream<T?> events,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final currentBeforeListening = currentValue();
  if (currentBeforeListening != null) return currentBeforeListening;

  final completer = Completer<T?>();
  late final StreamSubscription<T?> subscription;
  subscription = events.listen(
    (value) {
      if (value != null && !completer.isCompleted) completer.complete(value);
    },
    onError: (_) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  // Cierra la carrera entre la primera lectura y el registro del listener.
  final currentAfterListening = currentValue();
  if (currentAfterListening != null && !completer.isCompleted) {
    completer.complete(currentAfterListening);
  }

  try {
    return await completer.future.timeout(timeout, onTimeout: () => null);
  } finally {
    await subscription.cancel();
  }
}

class StaffAuthRestore {
  static const _pendingKey = 'staff_google_oauth_pending';
  static const _storageTimeout = Duration(seconds: 2);

  static Future<void> markPending() async {
    try {
      final preferences = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      await preferences.setBool(_pendingKey, true).timeout(_storageTimeout);
    } on TimeoutException {
      // El acceso administrativo debe continuar aunque falle el marcador local.
    }
  }

  static Future<bool> isPending() async {
    try {
      final preferences = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      return preferences.getBool(_pendingKey) == true;
    } on TimeoutException {
      return false;
    }
  }

  static Future<void> clear() async {
    try {
      final preferences = await SharedPreferences.getInstance().timeout(
        _storageTimeout,
      );
      await preferences.remove(_pendingKey).timeout(_storageTimeout);
    } on TimeoutException {
      // La limpieza del marcador nunca debe bloquear la navegación.
    }
  }
}
