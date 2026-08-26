# Informe de verificación del código fuente

Fecha de verificación inicial: 2026-08-09

Versión del código: 0.3.2+5

## Verificaciones ejecutadas en el entorno de construcción

- JSON válido para 68 productos y 25 preguntas.
- Cinco preguntas exactas por cada una de las cinco categorías.
- Identificadores de producto y pregunta sin duplicados.
- 64 productos individuales, 4 kits sugeridos y un producto preventivamente inhabilitado.
- 4.608 combinaciones completas recorridas con un validador independiente del motor.
- 3.984 combinaciones con coincidencia y 624 con no-match explícito.
- Cero violaciones detectadas de destinatario, tipo o presupuesto en el validador.
- YAML, manifest, JavaScript del service worker y balance estructural de archivos Dart validados.
- 68 rutas de imagen comprobadas contra los 68 IDs del catálogo: 64 productos
  individuales y 4 kits.
- Las 68 imágenes tienen lienzo WebP de 600 × 600 píxeles y proceden de las
  páginas fuente registradas en el catálogo de agosto.

## Actualización de cierre técnico - 2026-08-26

- Flutter 3.44.6 y Dart 3.12.2 verificados con `flutter doctor -v` sin problemas.
- `flutter analyze --no-pub`: sin problemas.
- `flutter test --no-pub`: 30 pruebas aprobadas.
- `flutter build web --release`: aprobado; salida renovada en `build/web`.
- `flutter build apk --debug`: aprobado; salida renovada en `build/app/outputs/flutter-apk/app-debug.apk`.
- La prueba integral fue ejecutada en el emulador Android 36 `medium_phone`: recorrido completo aprobado.
- La revisión visual en 1080 x 2400 confirmó bienvenida legible, controles completos y ausencia de desbordamientos.
- La prueba en el emulador detectó y permitió corregir el bloqueo del recomendador cuando Supabase no está configurado. El modo local ahora recomienda con el catálogo incluido y mantiene desactivado solamente el registro remoto de solicitudes.
- Las pruebas pgTAP no se ejecutaron en este equipo porque Docker Desktop no está instalado o activo. La CLI Supabase 2.114.0 detectó correctamente esa ausencia.

Las pruebas pgTAP deben verificarse con Supabase local antes de publicar; no impiden conservar este cierre como candidato de piloto técnico.

## Registro histórico de validación pendiente

El entorno de construcción no tenía Flutter/Dart instalado. Por eso no se afirma que `flutter analyze`, `flutter test` o `flutter build web` hayan pasado aquí. Ejecuta `scripts\verify_and_build.ps1` en el equipo Windows con Flutter estable antes de publicar.
