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

function Require-ReleaseKeystore {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Missing $Path. Copy android/key.properties.example and set the production keystore before building an Android release."
    }

    $properties = @{}
    foreach ($line in Get-Content $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
            continue
        }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }
        $properties[$parts[0].Trim()] = $parts[1].Trim()
    }

    $requiredKeys = @("storeFile", "storePassword", "keyAlias", "keyPassword")
    $missingKeys = $requiredKeys | Where-Object {
        -not $properties.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($properties[$_])
    }

    if ($missingKeys.Count -gt 0) {
        throw "android/key.properties is missing required values: $($missingKeys -join ', ')"
    }
}

function Get-VersionName {
    param([Parameter(Mandatory = $true)][string]$PubspecPath)

    $pubspec = Get-Content $PubspecPath -Raw
    if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+\d+\s*$') {
        return $matches[1]
    }

    throw "Could not parse versionName from $PubspecPath"
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$androidKeystorePropertiesPath = Join-Path $projectRoot "android\key.properties"
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
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
$androidReleaseAssetName = "app-release.apk"
$versionName = Get-VersionName -PubspecPath $pubspecPath
$expectedReleaseTag = "v$versionName"
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

    if (-not $SkipAndroidBuild) {
        $currentStep = "Validate Android release keystore"
        Require-ReleaseKeystore -Path $androidKeystorePropertiesPath
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
Write-Output "Expected Android release tag: $expectedReleaseTag"
Write-Output "Expected Android asset name: $androidReleaseAssetName"

if ($result -eq "FAILED") {
    Write-Output "Failed step: $failedStep"
    Write-Output "Error: $failureMessage"
}

exit $exitCode
