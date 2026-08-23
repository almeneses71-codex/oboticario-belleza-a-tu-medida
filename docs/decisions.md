# Decisiones técnicas y comerciales

1. La base ampliada prevalece sobre el expediente en productos: 64 individuales y 4 kits sugeridos.
2. El expediente prevalece en alcance, privacidad, PWA, WhatsApp, accesibilidad y criterios de aceptación.
3. La aplicación no usa backend, autenticación, pagos ni inteligencia artificial.
4. El motor es determinístico: filtros duros, puntajes visibles, desempate estable y no-match honesto.
5. Los cuatro kits se muestran como propuestas sugeridas, nunca como SKU oficial.
6. OB046 permanece inhabilitado hasta confirmar el código de variante.
7. El WhatsApp solo se configura mediante `--dart-define`; el repositorio no contiene un número inventado.
8. Las métricas son contadores locales anónimos. No identifican personas ni centralizan datos.
9. En escritorio se usa la ventana visual "Teléfono 2" de 430 px; en móvil la interfaz ocupa toda la pantalla.
10. Las reglas ampliadas están embebidas por opción en `questionnaire.json`; `scoring_rules.json` documenta el orden global.
11. Flutter 3.44 ya no genera service worker por defecto; el proyecto incorpora uno explícito y un aviso visible de desconexión.
