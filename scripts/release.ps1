param(
    [string]$DartDefinesFile = "config/dart_defines.prod.json",
    [string]$ReleaseTag = "",
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
    if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+\d+)?\s*$') {
        return $matches[1]
    }

    throw "Could not parse versionName from $PubspecPath"
}

function Confirm-ReleaseTag {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedReleaseTag,
        [string]$ReleaseTag = ""
    )

    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        return
    }

    if ($ReleaseTag.Trim() -ne $ExpectedReleaseTag) {
        throw "ReleaseTag '$ReleaseTag' does not match pubspec versionName. Expected '$ExpectedReleaseTag'. Update pubspec.yaml before building."
    }
}

function Convert-ToPosixSingleQuotedString {
    param([Parameter(Mandatory = $true)][string]$Value)

    return "'" + $Value + "'"
}

function Assert-PublicWebAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string[]]$ExpectedContentTypeHints
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Head
    } catch {
        throw "Public asset check failed for '$Url': $($_.Exception.Message)"
    }

    $contentType = [string]$response.Headers["Content-Type"]
    if ([string]::IsNullOrWhiteSpace($contentType)) {
        throw "Public asset check failed for '$Url': response did not include a Content-Type header."
    }

    $normalizedContentType = $contentType.ToLowerInvariant()
    $matchesExpectedType = $false
    foreach ($hint in $ExpectedContentTypeHints) {
        if ($normalizedContentType.Contains($hint.ToLowerInvariant())) {
            $matchesExpectedType = $true
            break
        }
    }

    if (-not $matchesExpectedType) {
        $expectedTypesDisplay = $ExpectedContentTypeHints -join ", "
        throw "Public asset check failed for '$Url': expected Content-Type containing one of [$expectedTypesDisplay], got '$contentType'. The server is likely returning an HTML fallback for a Flutter static asset."
    }
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$androidKeystorePropertiesPath = Join-Path $projectRoot "android\key.properties"
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$webBuildWorkaroundScriptPath = Join-Path $PSScriptRoot "prepare_flat_web_build.ps1"
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
$publicWebBaseUrl = if ([string]::IsNullOrWhiteSpace($PublicHostHeader)) {
    $null
} else {
    "https://$PublicHostHeader/deadline/"
}
$webDeployArchiveName = "deadline-web-$versionName.tar.gz"
$webDeployArchiveLocalPath = Join-Path ([IO.Path]::GetTempPath()) $webDeployArchiveName
$webDeployArchiveRemotePath = "/tmp/$webDeployArchiveName"
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
$webPublicVerifyStatus = if ($SkipWebDeploy -or [string]::IsNullOrWhiteSpace($PublicHostHeader)) {
    "SKIPPED"
} else {
    "PENDING"
}
$androidBuildStatus = if ($SkipAndroidBuild) { "SKIPPED" } else { "PENDING" }
$exitCode = 0

Set-Location $projectRoot

try {
    $currentStep = "Check required commands"
    Require-Command flutter
    if (-not $SkipWebDeploy) {
        Require-Command scp
        Require-Command ssh
        Require-Command tar
    }

    $currentStep = "Validate dart defines file"
    if (-not (Test-Path $DartDefinesFile)) {
        throw "Missing $DartDefinesFile. Copy config/dart_defines.prod.example.json and fill it first."
    }

    $currentStep = "Validate release tag"
    Confirm-ReleaseTag -ExpectedReleaseTag $expectedReleaseTag -ReleaseTag $ReleaseTag

    $defineArg = "--dart-define-from-file=$DartDefinesFile"

    $currentStep = "flutter pub get"
    Invoke-Step $currentStep {
        Invoke-NativeCommand -FilePath "flutter" -Arguments @("pub", "get")
    }

    $currentStep = "Build web release (/deadline/)"
    Invoke-Step $currentStep {
        Invoke-NativeCommand -FilePath "flutter" -Arguments @("build", "web", "--release", "--base-href", "/deadline/", $defineArg)
    }

    $currentStep = "Prepare web build for flat-host deployment"
    Invoke-Step $currentStep {
        & $webBuildWorkaroundScriptPath -WebBuildDir $webBuildPath
    }
    $webBuildStatus = "OK"

    if (-not $SkipWebDeploy) {
        $webBuildSourcePath = (Resolve-Path $webBuildPath).Path
        $webArtifacts = Get-ChildItem -LiteralPath $webBuildSourcePath -Force

        if ($webArtifacts.Count -eq 0) {
            throw "No web artifacts found in $webBuildSourcePath"
        }

        $currentStep = "Create web deploy archive"
        Invoke-Step $currentStep {
            if (Test-Path $webDeployArchiveLocalPath) {
                Remove-Item -LiteralPath $webDeployArchiveLocalPath -Force
            }
            Invoke-NativeCommand -FilePath "tar" -Arguments @(
                "-czf",
                $webDeployArchiveLocalPath,
                "-C",
                $webBuildSourcePath,
                "."
            )
        }

        $currentStep = "Upload web deploy archive to ${remote}:$webDeployArchiveRemotePath"
        Invoke-Step $currentStep {
            Invoke-NativeCommand -FilePath "scp" -Arguments @(
                $webDeployArchiveLocalPath,
                "${remote}:$webDeployArchiveRemotePath"
            )
        }

        $currentStep = "Extract web deploy archive on server"
        Invoke-Step $currentStep {
            $quotedRemoteArchivePath = Convert-ToPosixSingleQuotedString -Value $webDeployArchiveRemotePath
            $quotedServerWebDir = Convert-ToPosixSingleQuotedString -Value $serverWebDirNormalized
            $remoteCommand = @(
                "mkdir -p $quotedServerWebDir"
                "tar -xzf $quotedRemoteArchivePath -C $quotedServerWebDir"
                "rm -f $quotedRemoteArchivePath"
            ) -join " && "
            Invoke-NativeCommand -FilePath "ssh" -Arguments @($remote, $remoteCommand)
        }
        $webDeployStatus = "OK"

        if ($publicWebBaseUrl) {
            $currentStep = "Verify public web assets"
            Invoke-Step $currentStep {
                Assert-PublicWebAsset -Url $publicWebBaseUrl -ExpectedContentTypeHints @("text/html")
                Assert-PublicWebAsset -Url ($publicWebBaseUrl + "main.dart.js") -ExpectedContentTypeHints @("javascript")
                Assert-PublicWebAsset -Url ($publicWebBaseUrl + "__flat__assets__AssetManifest.bin.json") -ExpectedContentTypeHints @("json")
                Assert-PublicWebAsset -Url ($publicWebBaseUrl + "canvaskit.js") -ExpectedContentTypeHints @("javascript")
            }
            $webPublicVerifyStatus = "OK"
        }
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

if (Test-Path $webDeployArchiveLocalPath) {
    Remove-Item -LiteralPath $webDeployArchiveLocalPath -Force
}

Write-Output ""
Write-Output "Result: $result"
Write-Output "Web build: $webBuildStatus -> $webBuildPath"
Write-Output "Web deploy: $webDeployStatus -> $webDeployTarget"
if ($publicWebBaseUrl) {
    Write-Output "Web public verify: $webPublicVerifyStatus -> $publicWebBaseUrl"
}
Write-Output "Android build: $androidBuildStatus -> $androidApkPath"
Write-Output "Android versionName: $versionName"
Write-Output "Android signing: $($androidSigningInfo.Mode)"
Write-Output "Expected Android release tag: $expectedReleaseTag"
Write-Output "Expected Android asset name: $androidReleaseAssetName"

if ($result -eq "FAILED") {
    Write-Output "Failed step: $failedStep"
    Write-Output "Error: $failureMessage"
}

exit $exitCode
