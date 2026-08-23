# Guía de prueba y uso con WhatsApp

## 1. Ubicación del proyecto

Extrae el paquete de modo que el archivo `pubspec.yaml` quede en:

```text
C:\Proyectos\Boticario Belleza a tu Medida\pubspec.yaml
```

Evita crear una carpeta duplicada, por ejemplo `...\Boticario Belleza a tu Medida\oboticario_belleza_a_tu_medida\pubspec.yaml`.

## 2. Requisitos

- Flutter estable instalado.
- Google Chrome.
- VS Code con las extensiones Flutter y Dart.
- Un número comercial de WhatsApp en formato internacional, sin `+`, espacios ni guiones.

Desde PowerShell, comprueba el entorno:

```powershell
cd "C:\Proyectos\Boticario Belleza a tu Medida"
flutter doctor
flutter pub get
```

## 3. Ejecutar la prueba

Sustituye `57XXXXXXXXXX` por el número real:

```powershell
.\scripts\run_demo.ps1 -WhatsAppNumber "57XXXXXXXXXX" -AdvisorName "Dario y Ana"
```

La aplicación se abrirá en Chrome. Completa una ruta de cinco preguntas y comprueba los dos botones de WhatsApp.

## 4. Validar y compilar

```powershell
.\scripts\verify_and_build.ps1 -WhatsAppNumber "57XXXXXXXXXX" -AdvisorName "Dario y Ana"
```

La orden formatea el código, ejecuta el análisis, las pruebas unitarias, la prueba del recorrido y la compilación web. Si todo termina correctamente, la versión publicable queda en:

```text
C:\Proyectos\Boticario Belleza a tu Medida\build\web
```

## 5. Compartirla por WhatsApp

La carpeta `build\web` debe publicarse en un servicio HTTPS. Luego podrás enviar la URL por mensajes semipersonales, estados, redes o un código QR. La aplicación no vive dentro de WhatsApp: WhatsApp es el canal de distribución y cierre comercial.

## 6. Actualización semanal

Edita `assets\data\products.json` antes de compilar una nueva versión:

- `priceCop`: precio vigente en pesos, sin puntos.
- `available`: `true` si está disponible y `false` si está agotado.
- `eligible`: `false` si el registro no debe recomendarse.
- `updated`: fecha de revisión con formato `AAAA-MM-DD`.

Después vuelve a ejecutar `verify_and_build.ps1`. No habilites `OB046` hasta confirmar el código de su variante.

## 7. Antes de publicar

- Confirma el número real de WhatsApp.
- Verifica precios, códigos y disponibilidad.
- Prueba al menos una ruta de cada categoría.
- Confirma que el producto principal y la alternativa sean coherentes.
- Comprueba ambos botones de WhatsApp desde un celular.
- Revisa `docs\release_checklist.md`.
