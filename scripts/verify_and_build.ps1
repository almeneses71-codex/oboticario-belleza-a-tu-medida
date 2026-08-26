param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d{8,15}$')]
  [string]$WhatsAppNumber,

  [string]$AdvisorName = 'Dario y Ana'
)

$ErrorActionPreference = 'Stop'

flutter --version
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test

$ChromeDriver = Get-Command chromedriver -ErrorAction SilentlyContinue
if (-not $ChromeDriver) {
  throw 'No se encontro chromedriver en PATH. Instala una version compatible con Chrome para ejecutar la prueba integral web.'
}
$ChromeDriverProcess = Start-Process `
  -FilePath $ChromeDriver.Source `
  -ArgumentList '--port=4444' `
  -WindowStyle Hidden `
  -PassThru
try {
  flutter drive -d chrome `
    --driver=test_driver/integration_test.dart `
    --target=integration_test/full_flow_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'La prueba integral web fallo.' }
} finally {
  Stop-Process -Id $ChromeDriverProcess.Id -Force -ErrorAction SilentlyContinue
}
flutter build web --release `
  --dart-define="WHATSAPP_NUMBER=$WhatsAppNumber" `
  --dart-define="ADVISOR_NAME=$AdvisorName"

Write-Host 'Build listo en build\web' -ForegroundColor Green
