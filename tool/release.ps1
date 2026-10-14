<#
.SYNOPSIS
  Build + publish a Spoticlone release via gh cli (100% free stack).
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
Write-Host "=== Spoticlone release $Tag ===" -ForegroundColor Green

# 0. Preconditions.
foreach ($cmd in @("flutter", "gh")) {
  if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "$cmd not found on PATH"
  }
}
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "gh is not authenticated (run: gh auth login)" }

# 1. Stamp pubspec version (keep existing +N build number when present).
$pub = Get-Content "$Root\pubspec.yaml" -Raw
$build = "1"
if ($pub -match '(?m)^version:\s*[\d.]+\+(\d+)') { $build = $Matches[1] }
$pub = $pub -replace '(?m)^version:\s*.*$', "version: ${Version}+${build}"
Set-Content "$Root\pubspec.yaml" -Value $pub -NoNewline:$false
Write-Host "pubspec version -> ${Version}+${build}"

# 2. Notes default: commits since last tag.
if ([string]::IsNullOrWhiteSpace($Notes)) {
  $last = (git describe --tags --abbrev=0 2>$null)
  $range = if ($last) { "$last..HEAD" } else { "HEAD" }
  $Notes = (git log $range --pretty=format:"- %s" 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($Notes)) { $Notes = "Release $Tag" }
  git tag $Tag
  Write-Host "tagged $Tag (notes from git log)"
}

# 3. Builds.
Write-Host "-- Android APK --" -ForegroundColor Cyan
& flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
$Apk = "$Root\build\app\outputs\flutter-apk\app-release.apk"

$SetupExe = $null
if (-not $SkipWindows) {
  Write-Host "-- Windows exe + NSIS installer --" -ForegroundColor Cyan
  & flutter build windows -t lib/main_desktop.dart --release
  if ($LASTEXITCODE -ne 0) { throw "Windows build failed" }
  Copy-Item -Recurse -Force "$Root\desktop\python" `
    "$Root\build\windows\x64\runner\Release\python"
  $nsis = "C:\Program Files (x86)\NSIS\makensis.exe"
  if (!(Test-Path $nsis)) { throw "NSIS not found (winget install NSIS.NSIS)" }
  & $nsis "$Root\installer\spoticlone.nsi"
  if ($LASTEXITCODE -ne 0) { throw "NSIS compile failed" }
  $SetupExe = Get-ChildItem "$Root\installer\Spoticlone-Setup-*.exe" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  # Stamp installer version into the .nsi for next time.
  (Get-Content "$Root\installer\spoticlone.nsi") `
    -replace '!define APP_VERSION "[^"]*"', "!define APP_VERSION `"$Version`"" |
    Set-Content "$Root\installer\spoticlone.nsi"
  Write-Host "installer -> $($SetupExe.FullName)"
}

# 4. Publish.
$assets = @($Apk)
if ($SetupExe) { $assets += $SetupExe.FullName }
$Notes | Out-File "$env:TEMP\spoticlone-notes.md" -Encoding utf8
$ghArgs = @("release", "create", $Tag) + $assets +
  @("--title", "Release $Tag", "--notes-file", "$env:TEMP\spoticlone-notes.md")
if ($Draft) { $ghArgs += "--draft" } else { $ghArgs += "--latest" }
& gh @ghArgs
Write-Host "=== released $Tag ===" -ForegroundColor Green
Write-Host "In-app updater picks this up via the Releases API automatically."
