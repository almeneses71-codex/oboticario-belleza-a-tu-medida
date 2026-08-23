param(
  [ValidateScript({
    $_ -eq '' -or $_ -match '^\d{8,15}$'
  })]
  [string]$WhatsAppNumber = '573016792025',

  [string]$AdvisorName = 'Dario y Ana'
)

$ErrorActionPreference = 'Stop'

$FlutterCommand = 'flutter'
if (Test-Path 'C:\flutter\bin\flutter.bat') {
  $FlutterCommand = 'C:\flutter\bin\flutter.bat'
}

& $FlutterCommand pub get

$RunArguments = @(
  'run',
  '-d',
  'chrome',
  "--dart-define=ADVISOR_NAME=$AdvisorName"
)

if ($WhatsAppNumber -ne '') {
  $RunArguments += "--dart-define=WHATSAPP_NUMBER=$WhatsAppNumber"
}

Write-Host 'Abriendo oBoticario en Chrome - Telefono tipo 2...' -ForegroundColor Green
& $FlutterCommand @RunArguments
