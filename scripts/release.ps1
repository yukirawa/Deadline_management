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

. (Join-Path $PSScriptRoot "release_common.ps1")

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$androidKeystorePropertiesPath = Join-Path $projectRoot "android\key.properties"
$googleServicesJsonPath = Join-Path $projectRoot "android\app\google-services.json"
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$webBuildWorkaroundScriptPath = Join-Path $PSScriptRoot "prepare_flat_web_build.ps1"
$androidApplicationId = "jp.yukirawa.kigenkanri"
$androidVersionInfo = Get-AndroidVersionInfo -PubspecPath $pubspecPath
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
$versionName = $androidVersionInfo.VersionName
$versionCode = $androidVersionInfo.VersionCode
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
$releaseCertificateHashes = $null
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

    if (-not $SkipAndroidBuild) {
        $currentStep = "Validate Android release signing"
        if ($androidSigningInfo.Mode -ne "RELEASE") {
            throw "$($androidSigningInfo.Warning) Create android/key.properties from android/key.properties.example and point it to the same release keystore used by the installed app."
        }

        $currentStep = "Read Android release certificate hashes"
        $releaseCertificateHashes = Get-KeystoreCertificateHashes `
            -StoreFilePath $androidSigningInfo.StoreFilePath `
            -StorePassword $androidSigningInfo.StorePassword `
            -KeyAlias $androidSigningInfo.KeyAlias `
            -KeyPassword $androidSigningInfo.KeyPassword

        $currentStep = "Validate Firebase Android fingerprints"
        Assert-ReleaseCertificateRegistered `
            -GoogleServicesJsonPath $googleServicesJsonPath `
            -PackageName $androidApplicationId `
            -ReleaseCertificateSha1 $releaseCertificateHashes.SHA1
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
            Invoke-NativeCommand -FilePath "flutter" -Arguments @("build", "apk", "--release", $defineArg)
        }

        $currentStep = "Validate built Android APK signer"
        $apkCertificateHashes = Get-ApkCertificateHashes -ApkPath (Join-Path $projectRoot $androidApkPath)
        if ($apkCertificateHashes.SHA1 -ne $releaseCertificateHashes.SHA1) {
            throw "Built APK signer SHA-1 '$($apkCertificateHashes.SHA1)' does not match the production keystore SHA-1 '$($releaseCertificateHashes.SHA1)'. Do not publish this APK."
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
Write-Output "Android versionCode: $versionCode"
Write-Output "Android signing: $($androidSigningInfo.Mode)"
if ($releaseCertificateHashes) {
    Write-Output "Android release SHA-1: $($releaseCertificateHashes.SHA1)"
}
Write-Output "Expected Android release tag: $expectedReleaseTag"
Write-Output "Expected Android asset name: $androidReleaseAssetName"

if ($result -eq "FAILED") {
    Write-Output "Failed step: $failedStep"
    Write-Output "Error: $failureMessage"
}

exit $exitCode
