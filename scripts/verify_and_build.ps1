param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d{8,15}$')]
  [string]$WhatsAppNumber,

  [string]$AdvisorName = 'Dario y Ana'
)

$ErrorActionPreference = 'Stop'

flutter --version
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter test integration_test -d chrome
flutter build web --release `
  --dart-define="WHATSAPP_NUMBER=$WhatsAppNumber" `
  --dart-define="ADVISOR_NAME=$AdvisorName"

Write-Host 'Build listo en build\web' -ForegroundColor Green

