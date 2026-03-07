param(
    [string]$DartDefinesFile = "config/dart_defines.prod.json",
    [string]$ServerUser = "shunta",
    [string]$ServerHost = "yukirawa.jp",
    [string]$ServerWebDir = "/home/shunta/server/apps/web/main/deadline",
    [string]$ServerComposeFile = "/home/shunta/server/compose/web/compose.yaml",
    [string]$ServerComposeService = "nginx",
    [string]$PublicHostHeader = "yukirawa.jp",
    [switch]$SkipWebDeploy,
    [switch]$SkipAndroidBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' not found."
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

Require-Command flutter
if (-not $SkipWebDeploy) {
    Require-Command ssh
    Require-Command tar
}

if (-not (Test-Path $DartDefinesFile)) {
    throw "Missing $DartDefinesFile. Copy config/dart_defines.prod.example.json and fill it first."
}

$defineArg = "--dart-define-from-file=$DartDefinesFile"

Invoke-Step "flutter pub get" {
    flutter pub get
}

Invoke-Step "Build web release (/deadline/)" {
    flutter build web --release --base-href /deadline/ $defineArg
}

if (-not $SkipWebDeploy) {
    $remote = "$ServerUser@$ServerHost"
    $remoteTmp = "/tmp/deadline_web_$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"

    Invoke-Step "Upload web artifacts to $remote" {
        ssh $remote "set -e; mkdir -p '$remoteTmp' '$ServerWebDir'"
        tar -cf - -C build/web . | ssh $remote "set -e; tar -xf - -C '$remoteTmp'"
    }

    Invoke-Step "Activate web artifacts and restart web container" {
        $remoteCmd = @(
            "set -e",
            "find '$ServerWebDir' -mindepth 1 -maxdepth 1 -exec rm -rf {} +",
            "cp -a '$remoteTmp'/.' '$ServerWebDir'/",
            "rm -rf '$remoteTmp'",
            "docker compose -f '$ServerComposeFile' restart '$ServerComposeService'",
            "curl -fsSI http://127.0.0.1/deadline/ -H 'Host: $PublicHostHeader' >/dev/null",
            "curl -fsSI http://127.0.0.1/deadline/assets/fonts/MaterialIcons-Regular.otf -H 'Host: $PublicHostHeader' >/dev/null",
            "curl -fsSI http://127.0.0.1/deadline/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf -H 'Host: $PublicHostHeader' >/dev/null"
        ) -join "; "
        ssh $remote $remoteCmd
    }
}

if (-not $SkipAndroidBuild) {
    Invoke-Step "Build Android APK release" {
        flutter build apk --release $defineArg
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Web build: build/web"
if (-not $SkipAndroidBuild) {
    Write-Host "Android APK: build/app/outputs/flutter-apk/app-release.apk"
}
