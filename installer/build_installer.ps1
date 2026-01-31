param(
  [string]$Version = "",
  [string]$BunVersion = "1.3.5",
  [switch]$SkipFlutterBuild,
  [switch]$SkipMsi
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$flutter = Join-Path $root "flutter\\bin\\flutter.bat"
$guiDir = Join-Path $root "atlas_gui_flutter"
$distDir = Join-Path $root "dist"
$buildRoot = Join-Path $distDir "ATLAS"
$wxsFile = Join-Path $PSScriptRoot "ATLAS.wxs"
$licenseFile = Join-Path $PSScriptRoot "LICENSE.rtf"
$iconPath = Join-Path $root "atlas_gui_flutter\\windows\\runner\\resources\\app_icon.ico"

if (-not (Test-Path $wxsFile)) {
  throw "Missing WiX source file: $wxsFile"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $packageJson = Join-Path $root "package.json"
  if (Test-Path $packageJson) {
    $json = Get-Content $packageJson -Raw | ConvertFrom-Json
    if ($json.version) {
      $Version = [string]$json.version
    }
  }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = "1.0.0"
}

if (-not $SkipFlutterBuild) {
  if (-not (Test-Path $flutter)) {
    throw "Flutter not found at $flutter"
  }
  Push-Location $guiDir
  & $flutter build windows --release
  Pop-Location
}

if (Test-Path $buildRoot) {
  Remove-Item $buildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $buildRoot | Out-Null

$releaseDir = Join-Path $guiDir "build\\windows\\x64\\runner\\Release"
if (-not (Test-Path $releaseDir)) {
  throw "Release build not found: $releaseDir"
}
Copy-Item -Path (Join-Path $releaseDir "*") -Destination $buildRoot -Recurse -Force

$backendItems = @(
  "package.json",
  "bun.lockb",
  "src",
  "static",
  "public",
  "responses",
  "exports",
  "node_modules"
)

foreach ($item in $backendItems) {
  $srcPath = Join-Path $root $item
  if (Test-Path $srcPath) {
    Copy-Item -Path $srcPath -Destination (Join-Path $buildRoot $item) -Recurse -Force
  }
}

$bunDir = Join-Path $buildRoot "tools\\bun"
$bunExe = Join-Path $bunDir "bun.exe"
if (-not (Test-Path $bunExe)) {
  New-Item -ItemType Directory -Path $bunDir -Force | Out-Null
  $bunZip = Join-Path $distDir ("bun-{0}-windows-x64.zip" -f $BunVersion)
  if (-not (Test-Path $bunZip)) {
    $bunUrl = "https://github.com/oven-sh/bun/releases/download/bun-v$BunVersion/bun-windows-x64.zip"
    Write-Host "Downloading Bun $BunVersion..."
    Invoke-WebRequest -Uri $bunUrl -OutFile $bunZip
  }
  $bunTemp = Join-Path $distDir "bun_tmp"
  if (Test-Path $bunTemp) {
    Remove-Item $bunTemp -Recurse -Force
  }
  Expand-Archive -Path $bunZip -DestinationPath $bunTemp
  $bunExtracted = Get-ChildItem -Path $bunTemp -Filter "bun.exe" -Recurse | Select-Object -First 1
  if (-not $bunExtracted) {
    throw "bun.exe not found in downloaded archive."
  }
  Copy-Item -Path $bunExtracted.FullName -Destination $bunExe -Force
  Remove-Item $bunTemp -Recurse -Force
}

if ($SkipMsi) {
  Write-Host "Staged files at $buildRoot"
  exit 0
}

$wixExe = $null
$wixCmd = Get-Command "wix" -ErrorAction SilentlyContinue
if ($wixCmd) {
  $wixExe = $wixCmd.Source
}

if (-not $wixExe) {
$candidatePaths = @(
    $env:WIX,
    ($(if ($env:WIX) { Join-Path $env:WIX "wix.exe" } else { $null })),
    (Join-Path $env:ProgramFiles "WiX Toolset v4\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v4.0\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v5\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v5.0\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v6\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v6.0\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset\bin\wix.exe"),
    (Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe")
  )

  foreach ($candidate in $candidatePaths) {
    if ($candidate -and (Test-Path $candidate)) {
      $wixExe = $candidate
      break
    }
  }
}

if (-not $wixExe) {
  $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
  if (Test-Path $wingetRoot) {
    $found = Get-ChildItem -Path $wingetRoot -Filter wix.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
      $wixExe = $found.FullName
    }
  }
}

if (-not $wixExe) {
  throw "WiX Toolset not found. Ensure 'wix' is on PATH or set WIX to the install folder."
}

$msiOut = Join-Path $distDir ("ATLAS-{0}.msi" -f $Version)
& $wixExe build $wxsFile `
  -d BuildRoot="$buildRoot" `
  -d ProductVersion="$Version" `
  -d LicenseFile="$licenseFile" `
  -d IconPath="$iconPath" `
  -ext WixToolset.UI.wixext `
  -o "$msiOut"

Write-Host "MSI created: $msiOut"

$cleanupPaths = @(
  "ATLAS-setup-plain.cmd",
  "ATLAS-setup.cmd",
  "ATLAS-setup.ps1",
  "ATLAS-setup.sed",
  "ATLAS-Setup.exe",
  "ATLAS-Setup-fixed.exe",
  "ATLAS-Setup-gui.exe",
  "ATLAS-Setup-gui2.exe",
  "ATLAS-Setup-gui3.exe",
  "ATLAS-Setup-gui4.exe",
  "ATLAS-Setup-gui5.exe",
  "ATLAS-Setup-gui6.exe",
  "prep_config_msi.cmd",
  "bundle_src"
)

foreach ($item in $cleanupPaths) {
  $target = Join-Path $distDir $item
  if (Test-Path $target) {
    Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
