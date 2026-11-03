<#
.SYNOPSIS
  Construit l'installeur Windows d'Aika (Aika-vX.Y.Z-windows-x64-setup.exe) en local.

.DESCRIPTION
  Mêmes étapes que le job "build-windows" de .github/workflows/release.yml,
  sur ce PC et pour Windows uniquement :
    1. vérifie que app/pubspec.yaml et le script Inno Setup ont la même version ;
    2. vérifie les outils (Flutter, Rust, Inno Setup) ;
    3. installe les dépendances, lance flutter analyze et flutter test ;
    4. compile Aika en release (le cœur Rust est compilé par cargokit) ;
    5. ajoute les DLL Visual C++ et crée l'installeur avec Inno Setup ;
    6. écrit l'empreinte SHA-256 de l'installeur à côté de lui, dans dist\.

  À lancer depuis n'importe quel dossier :
    powershell -ExecutionPolicy Bypass -File support\scripts\release_windows.ps1

.PARAMETER SkipChecks
  Saute flutter analyze et flutter test (déconseillé pour une vraie release).

.PARAMETER Clean
  Lance flutter clean avant la compilation (build complet, plus long).

.PARAMETER StopRunning
  Ferme automatiquement Aika si elle tourne depuis le dossier de build
  (sinon le script s'arrête et demande de la fermer).
#>
param(
  [switch]$SkipChecks,
  [switch]$Clean,
  [switch]$StopRunning
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$app = Join-Path $repo 'app'
$issFile = Join-Path $repo 'support\scripts\compile_windows_exe-inno.iss'
$releaseDir = Join-Path $app 'build\windows\x64\runner\Release'

function Write-Step([string]$message) {
  Write-Host ''
  Write-Host "==> $message" -ForegroundColor Cyan
}

function Fail([string]$message) {
  Write-Host ''
  Write-Host "ERREUR : $message" -ForegroundColor Red
  exit 1
}

# Lance une commande externe et s'arrête si elle échoue.
function Invoke-Checked([string]$what, [scriptblock]$command) {
  & $command
  if ($LASTEXITCODE -ne 0) {
    Fail "$what a échoué (code $LASTEXITCODE)."
  }
}

# --- 1. Version -------------------------------------------------------------
Write-Step 'Vérification de la version'

$pubspecLine = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' | Select-Object -First 1
if (-not $pubspecLine) {
  Fail "app\pubspec.yaml doit contenir une ligne 'version: X.Y.Z+N'."
}
$version = $pubspecLine.Matches[0].Groups[1].Value
$buildNumber = $pubspecLine.Matches[0].Groups[2].Value

$issLine = Select-String -Path $issFile -Pattern '^#define MyAppVersion "(.+)"' | Select-Object -First 1
$issVersion = if ($issLine) { $issLine.Matches[0].Groups[1].Value } else { '' }
if ($issVersion -ne $version) {
  Fail "Version différente : pubspec.yaml = $version, compile_windows_exe-inno.iss = '$issVersion'. Mets les deux à jour."
}
Write-Host "Aika $version (build $buildNumber)"

# --- 2. Outils --------------------------------------------------------------
Write-Step 'Vérification des outils'

# Flutter : la version du projet via FVM si disponible, sinon celle du PATH.
$useFvm = (Test-Path (Join-Path $repo '.fvmrc')) -and (Get-Command fvm -ErrorAction SilentlyContinue)
# Lance flutter (via FVM si disponible) avec les arguments donnés.
function Invoke-Flutter([string]$what, [string[]]$flutterArgs) {
  if ($useFvm) {
    & fvm flutter @flutterArgs
  } else {
    & flutter @flutterArgs
  }
  if ($LASTEXITCODE -ne 0) {
    Fail "$what a échoué (code $LASTEXITCODE)."
  }
}
if (-not $useFvm -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Fail 'Flutter est introuvable dans le PATH.'
}
Write-Host ("Flutter : " + $(if ($useFvm) { 'via FVM (.fvmrc)' } else { (Get-Command flutter).Source }))

if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
  Fail "Rust (rustup) est introuvable : installe-le depuis https://rustup.rs (nécessaire pour compiler le cœur d'Aika)."
}
Write-Host ("Rust : " + (& rustc --version))

$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
  $cmd = Get-Command iscc -ErrorAction SilentlyContinue
  if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
  Fail "Inno Setup 6 est introuvable. Installe-le avec : winget install JRSoftware.InnoSetup"
}
Write-Host "Inno Setup : $iscc"

# Windows interdit de remplacer un .exe en cours d'exécution : une Aika lancée
# depuis le dossier de build (souvent cachée dans la zone de notification)
# ferait échouer la compilation à la toute fin (erreur LNK1104).
$running = @(Get-Process -Name aika -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith($releaseDir, [System.StringComparison]::OrdinalIgnoreCase)
  })
if ($running.Count -gt 0) {
  if ($StopRunning) {
    Write-Host "Fermeture d'Aika lancée depuis le dossier de build..." -ForegroundColor Yellow
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
  } else {
    Fail ("Aika est ouverte depuis le dossier de build ($releaseDir), ce qui bloquerait la compilation. " +
      "Quitte-la (clic droit sur l'icône de la zone de notification, puis Quitter) ou relance le script avec -StopRunning.")
  }
}

# --- 3. Dépendances, analyse, tests -----------------------------------------
Push-Location $app
try {
  if ($Clean) {
    Write-Step 'Nettoyage (flutter clean)'
    Invoke-Flutter 'flutter clean' @('clean')
  }

  Write-Step 'Dépendances'
  Invoke-Flutter 'flutter pub get (app)' @('pub', 'get')
  Push-Location (Join-Path $repo 'packages\localsend_isolates\rust_builder\cargokit\build_tool')
  try {
    Invoke-Flutter 'flutter pub get (cargokit)' @('pub', 'get')
  } finally {
    Pop-Location
  }

  if ($SkipChecks) {
    Write-Host 'Analyse et tests sautés (-SkipChecks).' -ForegroundColor Yellow
  } else {
    Write-Step 'Analyse (flutter analyze)'
    Invoke-Flutter 'flutter analyze' @('analyze', '--no-pub')
    Write-Step 'Tests (flutter test)'
    Invoke-Flutter 'flutter test' @('test', '--no-pub')
  }

  # --- 4. Compilation -------------------------------------------------------
  Write-Step 'Compilation release (flutter build windows)'
  Invoke-Flutter 'flutter build windows' @('build', 'windows', '--release', '--no-pub')
} finally {
  Pop-Location
}

if (-not (Test-Path (Join-Path $releaseDir 'aika.exe'))) {
  Fail "aika.exe introuvable dans $releaseDir : la compilation n'a rien produit."
}

# --- 5. Installeur ----------------------------------------------------------
Write-Step 'Ajout des DLL Visual C++'
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item (Join-Path $repo "support\build\windows\x64\$dll") $releaseDir -Force
}

Write-Step "Création de l'installeur (Inno Setup)"
Push-Location $repo
try {
  Invoke-Checked 'Inno Setup' { & $iscc /Q $issFile }
} finally {
  Pop-Location
}

$installer = Join-Path $repo "dist\Aika-v$version-windows-x64-setup.exe"
if (-not (Test-Path $installer)) {
  Fail "Installeur attendu introuvable : $installer"
}

# --- 6. Empreinte -----------------------------------------------------------
$hash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLower()
$hashFile = Join-Path $repo "dist\Aika-v$version-windows-x64-setup.exe.sha256"
"$hash  Aika-v$version-windows-x64-setup.exe" | Set-Content -Path $hashFile -Encoding ascii

$sizeMb = [math]::Round((Get-Item $installer).Length / 1MB, 1)
Write-Host ''
Write-Host "Installeur prêt : $installer ($sizeMb Mo)" -ForegroundColor Green
Write-Host "SHA-256 : $hash"
Write-Host "Empreinte enregistrée dans : $hashFile"
