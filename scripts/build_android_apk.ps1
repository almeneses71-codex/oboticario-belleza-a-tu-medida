param(
  [string]$FlutterPath = "C:\flutter\bin\flutter.bat",
  [string]$WhatsAppNumber = "573016792025",
  [string]$AdvisorName = "Dario y Ana"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Set-Location $ProjectRoot

if (-not (Test-Path $FlutterPath)) {
  throw "No se encontro Flutter en: $FlutterPath"
}

if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
  throw "No se encontro pubspec.yaml en: $ProjectRoot"
}

if ($WhatsAppNumber -notmatch '^\d{8,15}$') {
  throw "El numero de WhatsApp debe tener entre 8 y 15 digitos, sin +, espacios ni guiones."
}

Write-Host "Preparando plataforma Android..." -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $ProjectRoot "android"))) {
  & $FlutterPath create --platforms=android --org com.darioyana --project-name oboticario_belleza_a_tu_medida .
  if ($LASTEXITCODE -ne 0) { throw "Flutter no pudo crear la plataforma Android." }
}

Write-Host "Descargando dependencias..." -ForegroundColor Cyan
& $FlutterPath pub get
if ($LASTEXITCODE -ne 0) { throw "Fallo flutter pub get." }

Write-Host "Analizando el proyecto..." -ForegroundColor Cyan
& $FlutterPath analyze
if ($LASTEXITCODE -ne 0) { throw "Flutter analyze encontro errores. La APK no se genero." }

Write-Host "Ejecutando pruebas..." -ForegroundColor Cyan
& $FlutterPath test
if ($LASTEXITCODE -ne 0) { throw "Las pruebas fallaron. La APK no se genero." }

Write-Host "Generando APK de prueba..." -ForegroundColor Cyan
& $FlutterPath build apk --debug `
  --dart-define="WHATSAPP_NUMBER=$WhatsAppNumber" `
  --dart-define="ADVISOR_NAME=$AdvisorName"
if ($LASTEXITCODE -ne 0) { throw "Flutter no pudo generar la APK." }

$ApkSource = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-debug.apk"
$ApkTarget = Join-Path $ProjectRoot "oBoticario_Belleza_a_tu_Medida_PRUEBA.apk"

if (-not (Test-Path $ApkSource)) {
  throw "La compilacion termino, pero no se encontro: $ApkSource"
}

Copy-Item $ApkSource $ApkTarget -Force

Write-Host ""
Write-Host "APK creada correctamente:" -ForegroundColor Green
Write-Host $ApkTarget -ForegroundColor Green
Write-Host "Copiala al celular Android e instalala para realizar la prueba."
