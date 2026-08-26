# oBoticario Belleza a tu Medida

Aplicación Flutter Web/PWA para asesoría independiente de productos O Boticário. Formula cinco preguntas por categoría, aplica reglas determinísticas, presenta una recomendación y permite registrar una solicitud comercial en Supabase antes de continuar por WhatsApp.

La aplicación no se instala dentro de WhatsApp. Se publica como enlace web y se comparte por chats, estados o código QR; el resultado abre una conversación de WhatsApp con el mensaje listo.

## Contenido funcional

- Ventana compacta "Teléfono 2" en escritorio y pantalla completa en móvil.
- Cinco categorías y 25 preguntas.
- 64 productos individuales y 4 kits comerciales sugeridos.
- 64 fotografías de producto y 4 composiciones de kits verificadas desde el
  catálogo de agosto.
- Filtros obligatorios de destinatario, tipo y presupuesto.
- Disponibilidad, elegibilidad, precio y fecha editables en JSON.
- No-match sin recomendaciones forzadas.
- WhatsApp configurable y mensaje codificado mediante `Uri`.
- Contadores locales anónimos de aperturas, cuestionarios y clics.
- Solicitudes, disponibilidad, atribución, operación comercial y auditoría mediante Supabase cuando se configura.
- Funcionamiento local limitado al recomendador cuando Supabase no está configurado; el envío de solicitudes queda desactivado de forma explícita.
- PWA instalable y responsive.
- Service worker propio para conservar el shell y recursos ya visitados.

## Preparación en Windows

Abre PowerShell dentro de:

```text
C:\Proyectos\Boticario Belleza a tu Medida
```

Comprueba Flutter:

```powershell
flutter doctor
flutter pub get
```

## Ejecutar el demo

El número debe escribirse en formato internacional, sin `+`, espacios ni guiones. Ejemplo de estructura colombiana: `57` seguido del número móvil real.

```powershell
flutter run -d chrome --dart-define=WHATSAPP_NUMBER=57XXXXXXXXXX --dart-define=ADVISOR_NAME="Dario y Ana"
```

También puedes usar el script incluido:

```powershell
.\scripts\run_demo.ps1 -WhatsAppNumber "57XXXXXXXXXX"
```

## Abrir directamente como Teléfono 2

Haz doble clic en `ABRIR_APP_TELEFONO_2.bat`, o ejecuta:

```powershell
.\scripts\run_phone_2.ps1
```

La aplicación usa internamente un lienzo "Teléfono 2" de 390 x 844 centrado en
Chrome. El script ya utiliza el WhatsApp comercial configurado y evita enviar a
Chrome parámetros de tamaño que puedan convertirse en pestañas `0.0.x.x`.

La versión 0.3.4 incluye las fotografías `OB001.webp` a `OB064.webp` y las
composiciones `KIT01.webp` a `KIT04.webp`. La ruta se resuelve automáticamente
por el ID estable de cada producto o kit.

Sin `WHATSAPP_NUMBER`, la app funciona completa, pero mantiene desactivados los botones de contacto y explica cómo configurarlos.

## Verificación obligatoria

```powershell
dart format lib test integration_test test_driver
flutter analyze
flutter test
chromedriver --port=4444
flutter drive -d chrome --driver=test_driver/integration_test.dart --target=integration_test/full_flow_test.dart
flutter build web --release --dart-define=WHATSAPP_NUMBER=57XXXXXXXXXX --dart-define=ADVISOR_NAME="Dario y Ana"
```

La prueba integral web requiere un ChromeDriver compatible con la versión de Chrome instalada. El sitio compilado queda en `build\web`.

Para habilitar disponibilidad y registro de solicitudes agrega también las variables de compilación `SUPABASE_URL` y `SUPABASE_ANON_KEY`. No guardes la clave en el repositorio.

## Crear una APK de prueba para Android

Haz doble clic en `CREAR_APK_ANDROID.bat`. El proceso crea la plataforma
Android si todavía no existe, ejecuta análisis y pruebas, y compila una APK
debug con el WhatsApp comercial configurado.

Al finalizar encontrarás:

```text
oBoticario_Belleza_a_tu_Medida_PRUEBA.apk
```

También puedes ejecutarlo desde PowerShell:

```powershell
.\scripts\build_android_apk.ps1
```

Para ejecutar toda la verificación y compilar en una sola orden:

```powershell
.\scripts\verify_and_build.ps1 -WhatsAppNumber "57XXXXXXXXXX"
```

## Publicar

Publica el contenido de `build\web` en un hosting HTTPS. Antes de compartir el enlace, completa la lista de `docs/release_checklist.md`.

## Fuente de datos

- `assets/data/products.json`: catálogo, precios, disponibilidad y kits.
- `assets/data/questionnaire.json`: preguntas, filtros y puntajes.
- `assets/data/scoring_rules.json`: orden global del motor y desempates.

El número de WhatsApp no se guarda en esos archivos ni se repite en el código.

Consulta `docs/GUIA_PRUEBA_Y_WHATSAPP.md` para instalar el proyecto en Windows, probarlo y preparar su publicación.
