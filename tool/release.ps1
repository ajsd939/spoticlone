<#
.SYNOPSIS
  Build + publish a Nocrift release via gh cli (100% free stack).
.EXAMPLE
  .\tool\release.ps1 -Version 1.1.0 -Notes "Playlists are here"
  .\tool\release.ps1 -Version 1.1.0            # notes from git log
  .\tool\release.ps1 -Version 1.1.0 -Draft     # draft release, publish later
#>
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$Notes = "",
  [switch]$Draft,
  [switch]$SkipWindows
)

$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
Set-Location $Root

$Tag = "v$Version"
Write-Host "=== Nocrift release $Tag ===" -ForegroundColor Green

# 0. Preconditions (background shells often lack user PATH entries,
# so resolve flutter/gh with fallbacks instead of trusting PATH).
function Resolve-Tool($name, $fallback) {
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  if ($fallback -and (Test-Path $fallback)) { return $fallback }
  throw "$name not found (checked PATH and $fallback)"
}
$Flutter = Resolve-Tool "flutter" `
  "C:\Users\Filip\flutter-sdk\flutter\bin\flutter.bat"
$Gh = Resolve-Tool "gh" $null
& $Gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "gh is not authenticated (run: gh auth login)" }

# 1. Stamp pubspec version (monotonic build number for versionCode).
$pub = Get-Content "$Root\pubspec.yaml" -Raw
$build = "1"
if ($pub -match '(?m)^version:\s*[\d.]+\+(\d+)') { $build = "$([int]$Matches[1] + 1)" }
$pub = $pub -replace '(?m)^version:\s*.*$', "version: ${Version}+${build}"
Set-Content "$Root\pubspec.yaml" -Value $pub -NoNewline:$false
# Stamp installer version up front (it used to be stamped AFTER makensis,
# so every release shipped with the previous version baked in).
(Get-Content "$Root\installer\spoticlone.nsi") `
  -replace '!define APP_VERSION "[^"]*"', "!define APP_VERSION `"$Version`"" |
  Set-Content "$Root\installer\spoticlone.nsi"
Write-Host "pubspec version -> ${Version}+${build}"

# 2. Notes default: commits since last tag (before the release commit).
if ([string]::IsNullOrWhiteSpace($Notes)) {
  $last = (git describe --tags --abbrev=0 2>$null)
  $range = if ($last) { "$last..HEAD" } else { "HEAD" }
  $Notes = (git log $range --pretty=format:"- %s" 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($Notes)) { $Notes = "Release $Tag" }
  Write-Host "notes from git log"
}

# 2b. Commit the stamps so the tag points at exactly what was built.
if ((git status --porcelain pubspec.yaml installer/spoticlone.nsi) -ne $null) {
  git add pubspec.yaml installer/spoticlone.nsi
  git commit -q -m "Release $Tag"
  Write-Host "committed version stamps"
}

# 3. Builds.
Write-Host "-- Android APK --" -ForegroundColor Cyan
& $Flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
$Apk = "$Root\build\app\outputs\flutter-apk\app-release.apk"

$SetupExe = $null
if (-not $SkipWindows) {
  Write-Host "-- Windows exe + NSIS installer --" -ForegroundColor Cyan
  & $Flutter build windows -t lib/main_desktop.dart --release
  if ($LASTEXITCODE -ne 0) { throw "Windows build failed" }
  Copy-Item -Recurse -Force "$Root\desktop\python" `
    "$Root\build\windows\x64\runner\Release\python"
  $nsis = "C:\Program Files (x86)\NSIS\makensis.exe"
  if (!(Test-Path $nsis)) { throw "NSIS not found (winget install NSIS.NSIS)" }
  & $nsis "$Root\installer\spoticlone.nsi"
  if ($LASTEXITCODE -ne 0) { throw "NSIS compile failed" }
  $SetupExe = Get-ChildItem "$Root\installer\Nocrift-Setup-*.exe" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Write-Host "installer -> $($SetupExe.FullName)"
  # Portable zip (versioned, replaces any older ones).
  $PortableZip = "$Root\dist\Nocrift-Portable-$Version.zip"
  New-Item -ItemType Directory -Force -Path "$Root\dist" | Out-Null
  Remove-Item "$Root\dist\Nocrift-Portable-*.zip" -Force `
    -ErrorAction SilentlyContinue
  Compress-Archive -Path "$Root\build\windows\x64\runner\Release\*" `
    -DestinationPath $PortableZip
  Write-Host "portable -> $PortableZip"
}

# 4. Tag only after green builds (a failed build must not leave
# a stray tag), then publish.
git tag $Tag
git push origin $Tag
$assets = @($Apk)
if ($SetupExe) { $assets += $SetupExe.FullName }
if (($PortableZip) -and (Test-Path $PortableZip)) {
  $assets += $PortableZip
}
$Notes | Out-File "$env:TEMP\spoticlone-notes.md" -Encoding utf8
$ghArgs = @("release", "create", $Tag) + $assets +
  @("--title", "Release $Tag", "--notes-file", "$env:TEMP\spoticlone-notes.md")
if ($Draft) { $ghArgs += "--draft" } else { $ghArgs += "--latest" }
& $Gh @ghArgs
Write-Host "=== released $Tag ===" -ForegroundColor Green
Write-Host "In-app updater picks this up via the Releases API automatically."
