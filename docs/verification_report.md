# Informe de verificación del código fuente

Fecha de verificación inicial: 2026-08-09

Versión del código: 0.3.4+8

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
- Las 40 migraciones fueron aplicadas correctamente al proyecto remoto de Supabase.
- El APK conectado al proyecto remoto fue instalado y probado en el emulador Android 36.
- La campaña Amor y Amistad 2026 apareció, permitió un giro real, otorgó 5 % de descuento y registró la solicitud de prueba `OBM-260826-WEB-0001`.
- Durante la prueba se corrigió el precio local de Egeo Dolce y Egeo Choc High para igualarlo al precio protegido por el servidor ($156.900 COP).
- Las pruebas pgTAP remotas quedaron pendientes porque la extensión `pgtap` no está disponible en el proyecto alojado. La lógica principal fue validada mediante el flujo integral contra Supabase.

Las pruebas pgTAP deben verificarse en un entorno local con la extensión disponible antes de publicar; no impiden conservar este cierre como candidato de piloto técnico.

## Registro histórico de validación pendiente

El entorno de construcción no tenía Flutter/Dart instalado. Por eso no se afirma que `flutter analyze`, `flutter test` o `flutter build web` hayan pasado aquí. Ejecuta `scripts\verify_and_build.ps1` en el equipo Windows con Flutter estable antes de publicar.
