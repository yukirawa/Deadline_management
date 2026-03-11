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

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    $nativeExitCode = $LASTEXITCODE
    if ($nativeExitCode -ne 0) {
        $joinedArguments = if ($Arguments.Count -gt 0) {
            $Arguments -join " "
        } else {
            ""
        }
        throw "Command failed with exit code ${nativeExitCode}: $FilePath $joinedArguments".TrimEnd()
    }
}

function Get-AndroidSigningInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $requiredKeys = @("storeFile", "storePassword", "keyAlias", "keyPassword")

    if (-not (Test-Path $Path)) {
        return [PSCustomObject]@{
            Mode = "DEBUG"
            Warning = "android/key.properties was not found. Android release build will use debug signing."
        }
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

    $missingKeys = $requiredKeys | Where-Object {
        -not $properties.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($properties[$_])
    }

    if ($missingKeys.Count -gt 0) {
        return [PSCustomObject]@{
            Mode = "DEBUG"
            Warning = "android/key.properties is missing required values ($($missingKeys -join ', ')). Android release build will use debug signing."
        }
    }

    return [PSCustomObject]@{
        Mode = "RELEASE"
        Warning = $null
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
$androidSigningInfo = if ($SkipAndroidBuild) {
    [PSCustomObject]@{
        Mode = "SKIPPED"
        Warning = $null
    }
} else {
    Get-AndroidSigningInfo -Path $androidKeystorePropertiesPath
}

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
        Require-Command scp
    }

    $currentStep = "Validate dart defines file"
    if (-not (Test-Path $DartDefinesFile)) {
        throw "Missing $DartDefinesFile. Copy config/dart_defines.prod.example.json and fill it first."
    }

    $defineArg = "--dart-define-from-file=$DartDefinesFile"

    $currentStep = "flutter pub get"
    Invoke-Step $currentStep {
        Invoke-NativeCommand -FilePath "flutter" -Arguments @("pub", "get")
    }

    $currentStep = "Build web release (/deadline/)"
    Invoke-Step $currentStep {
        Invoke-NativeCommand -FilePath "flutter" -Arguments @("build", "web", "--release", "--base-href", "/deadline/", $defineArg)
    }
    $webBuildStatus = "OK"

    if (-not $SkipWebDeploy) {
        $remoteTmp = "/tmp/deadline_web_$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        $webBuildSourcePath = (Resolve-Path $webBuildPath).Path

        $currentStep = "Upload web artifacts to $remote"
        Invoke-Step $currentStep {
            Invoke-NativeCommand -FilePath "ssh" -Arguments @(
                $remote,
                "mkdir -p `"$remoteTmp`" `"$serverWebDirNormalized`""
            )
            Invoke-NativeCommand -FilePath "scp" -Arguments @(
                "-r",
                $webBuildSourcePath,
                "${remote}:$remoteTmp/"
            )
        }

        $currentStep = "Activate web artifacts and restart web container"
        Invoke-Step $currentStep {
            $remoteCmd = @(
                "set -e",
                "find `"$serverWebDirNormalized`" -mindepth 1 -maxdepth 1 -exec rm -rf {} +",
                "cp -a `"$remoteTmp/web/.`" `"$serverWebDirNormalized/`"",
                "rm -rf `"$remoteTmp`"",
                "docker compose -f `"$ServerComposeFile`" restart `"$ServerComposeService`"",
                "curl -fsSI http://127.0.0.1/deadline/ -H `"Host: $PublicHostHeader`" >/dev/null",
                "curl -fsSI http://127.0.0.1/deadline/assets/fonts/MaterialIcons-Regular.otf -H `"Host: $PublicHostHeader`" >/dev/null",
                "curl -fsSI http://127.0.0.1/deadline/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf -H `"Host: $PublicHostHeader`" >/dev/null"
            ) -join "; "
            Invoke-NativeCommand -FilePath "ssh" -Arguments @($remote, $remoteCmd)
        }
        $webDeployStatus = "OK"
    }

    if (-not $SkipAndroidBuild) {
        $currentStep = "Build Android APK release"
        Invoke-Step $currentStep {
            if ($androidSigningInfo.Warning) {
                Write-Warning $androidSigningInfo.Warning
            }
            Invoke-NativeCommand -FilePath "flutter" -Arguments @("build", "apk", "--release", $defineArg)
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
Write-Output "Android signing: $($androidSigningInfo.Mode)"
Write-Output "Expected Android release tag: $expectedReleaseTag"
Write-Output "Expected Android asset name: $androidReleaseAssetName"

if ($result -eq "FAILED") {
    Write-Output "Failed step: $failedStep"
    Write-Output "Error: $failureMessage"
}

exit $exitCode
