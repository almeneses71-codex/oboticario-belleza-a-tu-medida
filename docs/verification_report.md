# Informe de verificación del código fuente

Fecha: 2026-08-09

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

## Validación pendiente en Windows

El entorno de construcción no tenía Flutter/Dart instalado. Por eso no se afirma que `flutter analyze`, `flutter test` o `flutter build web` hayan pasado aquí. Ejecuta `scripts\verify_and_build.ps1` en el equipo Windows con Flutter estable antes de publicar.
