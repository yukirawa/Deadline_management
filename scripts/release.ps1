param(
    [string]$DartDefinesFile = "config/dart_defines.prod.json",
    [string]$ServerUser = "shunta",
    [string]$ServerHost = "192.168.100.99",
    [string]$ServerWebDir = "/home/shunta/server/apps/web/main/deadline/",
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
$serverWebDirNormalized = $ServerWebDir.Trim().TrimEnd("/")
if ([string]::IsNullOrWhiteSpace($serverWebDirNormalized)) {
    throw "ServerWebDir must not be empty."
}

$serverWebDirDisplay = if ($serverWebDirNormalized -eq "/") {
    "/"
} else {
    "$serverWebDirNormalized/"
}

$remote = "$ServerUser@$ServerHost"
$webBuildPath = "build/web"
$androidApkPath = "build/app/outputs/flutter-apk/app-release.apk"
$webDeployTarget = "${remote}:$serverWebDirDisplay"

$result = "SUCCESS"
$failedStep = $null
$failureMessage = $null
$currentStep = "Initialization"
$webBuildStatus = "SKIPPED"
$webDeployStatus = if ($SkipWebDeploy) { "SKIPPED" } else { "PENDING" }
$androidBuildStatus = if ($SkipAndroidBuild) { "SKIPPED" } else { "PENDING" }
$exitCode = 0

Set-Location $projectRoot

try {
    $currentStep = "Check required commands"
    Require-Command flutter
    if (-not $SkipWebDeploy) {
        Require-Command ssh
        Require-Command tar
    }

    $currentStep = "Validate dart defines file"
    if (-not (Test-Path $DartDefinesFile)) {
        throw "Missing $DartDefinesFile. Copy config/dart_defines.prod.example.json and fill it first."
    }

    $defineArg = "--dart-define-from-file=$DartDefinesFile"

    $currentStep = "flutter pub get"
    Invoke-Step $currentStep {
        flutter pub get
    }

    $currentStep = "Build web release (/deadline/)"
    Invoke-Step $currentStep {
        flutter build web --release --base-href /deadline/ $defineArg
    }
    $webBuildStatus = "OK"

    if (-not $SkipWebDeploy) {
        $remoteTmp = "/tmp/deadline_web_$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"

        $currentStep = "Upload web artifacts to $remote"
        Invoke-Step $currentStep {
            ssh $remote "set -e; mkdir -p '$remoteTmp' '$serverWebDirNormalized'"
            tar -cf - -C $webBuildPath . | ssh $remote "set -e; tar -xf - -C '$remoteTmp'"
        }

        $currentStep = "Activate web artifacts and restart web container"
        Invoke-Step $currentStep {
            $remoteCmd = @(
                "set -e",
                "find '$serverWebDirNormalized' -mindepth 1 -maxdepth 1 -exec rm -rf {} +",
                "cp -a '$remoteTmp'/.' '$serverWebDirNormalized'/",
                "rm -rf '$remoteTmp'",
                "docker compose -f '$ServerComposeFile' restart '$ServerComposeService'",
                "curl -fsSI http://127.0.0.1/deadline/ -H 'Host: $PublicHostHeader' >/dev/null",
                "curl -fsSI http://127.0.0.1/deadline/assets/fonts/MaterialIcons-Regular.otf -H 'Host: $PublicHostHeader' >/dev/null",
                "curl -fsSI http://127.0.0.1/deadline/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf -H 'Host: $PublicHostHeader' >/dev/null"
            ) -join "; "
            ssh $remote $remoteCmd
        }
        $webDeployStatus = "OK"
    }

    if (-not $SkipAndroidBuild) {
        $currentStep = "Build Android APK release"
        Invoke-Step $currentStep {
            flutter build apk --release $defineArg
        }
        $androidBuildStatus = "OK"
    }
} catch {
    $result = "FAILED"
    $failedStep = $currentStep
    $failureMessage = $_.Exception.Message
    $exitCode = 1
}

Write-Output ""
Write-Output "Result: $result"
Write-Output "Web build: $webBuildStatus -> $webBuildPath"
Write-Output "Web deploy: $webDeployStatus -> $webDeployTarget"
Write-Output "Android build: $androidBuildStatus -> $androidApkPath"

if ($result -eq "FAILED") {
    Write-Output "Failed step: $failedStep"
    Write-Output "Error: $failureMessage"
}

exit $exitCode
