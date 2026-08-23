param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d{8,15}$')]
  [string]$WhatsAppNumber,

  [string]$AdvisorName = 'Dario y Ana'
)

$ErrorActionPreference = 'Stop'

flutter pub get
flutter run -d chrome `
  --dart-define="WHATSAPP_NUMBER=$WhatsAppNumber" `
  --dart-define="ADVISOR_NAME=$AdvisorName"

