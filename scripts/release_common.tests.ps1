$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "release_common.ps1")

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$ExpectedMessagePart
    )

    try {
        & $Action
    } catch {
        if ($_.Exception.Message -like "*$ExpectedMessagePart*") {
            return
        }

        throw "Expected error containing '$ExpectedMessagePart' but got: $($_.Exception.Message)"
    }

    throw "Expected the action to throw an error containing '$ExpectedMessagePart'."
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("deadline-release-common-tests-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $pubspecPath = Join-Path $tempRoot "pubspec.yaml"
    Set-Content -Path $pubspecPath -Value @"
name: sample
version: 1.2.3+4
"@
    $versionInfo = Get-AndroidVersionInfo -PubspecPath $pubspecPath
    Assert-Equal -Actual $versionInfo.VersionName -Expected "1.2.3" -Message "VersionName parsing failed."
    Assert-Equal -Actual $versionInfo.VersionCode -Expected 4 -Message "VersionCode parsing failed."

    $missingBuildPubspecPath = Join-Path $tempRoot "pubspec_no_build.yaml"
    Set-Content -Path $missingBuildPubspecPath -Value @"
name: sample
version: 1.2.3
"@
    Assert-Throws -Action {
        Get-AndroidVersionInfo -PubspecPath $missingBuildPubspecPath
    } -ExpectedMessagePart "X.Y.Z+N"

    $googleServicesPath = Join-Path $tempRoot "google-services.json"
    Set-Content -Path $googleServicesPath -Value @"
{
  "client": [
    {
      "client_info": {
        "android_client_info": {
          "package_name": "jp.yukirawa.kigenkanri"
        }
      },
      "oauth_client": [
        {
          "client_type": 1,
          "android_info": {
            "package_name": "jp.yukirawa.kigenkanri",
            "certificate_hash": "11448711bcb8368887aa969e61a67c2beaa174a6"
          }
        },
        {
          "client_type": 1,
          "android_info": {
            "package_name": "jp.yukirawa.kigenkanri",
            "certificate_hash": "b21ed33311d34d0777e97b467ba7528878946f13"
          }
        }
      ]
    }
  ]
}
"@
    $registeredHashes = @(Get-GoogleServicesAndroidCertificateHashes `
        -GoogleServicesJsonPath $googleServicesPath `
        -PackageName "jp.yukirawa.kigenkanri")
    Assert-Equal -Actual $registeredHashes.Count -Expected 2 -Message "Expected both debug and release certificate hashes."
    Assert-Equal -Actual $registeredHashes[1] -Expected "b21ed33311d34d0777e97b467ba7528878946f13" -Message "Release certificate hash was not normalized correctly."

    Assert-Throws -Action {
        Assert-ReleaseCertificateRegistered `
            -GoogleServicesJsonPath $googleServicesPath `
            -PackageName "jp.yukirawa.kigenkanri" `
            -ReleaseCertificateSha1 "AA:BB:CC"
    } -ExpectedMessagePart "does not contain the production SHA-1"

    $parsedKeytoolHashes = Get-CertificateHashesFromText -Lines @(
        "SHA1: B2:1E:D3:33:11:D3:4D:07:77:E9:7B:46:7B:A7:52:88:78:94:6F:13",
        "SHA256: 3D:79:9F:FE:F5:09:DF:07:66:FB:9D:1C:C6:AC:22:91:4E:CE:F5:67:8B:69:D6:22:4D:0C:B8:A2:FA:49:EE:AB"
    )
    Assert-Equal -Actual $parsedKeytoolHashes.SHA1 -Expected "b21ed33311d34d0777e97b467ba7528878946f13" -Message "Failed to parse keytool SHA-1 output."
    Assert-Equal -Actual $parsedKeytoolHashes.SHA256 -Expected "3d799ffef509df0766fb9d1cc6ac22914ecef5678b69d6224d0cb8a2fa49eeab" -Message "Failed to parse keytool SHA-256 output."

    $parsedApkHashes = Get-CertificateHashesFromText -Lines @(
        "Signer #1 certificate SHA-256 digest: 3d799ffef509df0766fb9d1cc6ac22914ecef5678b69d6224d0cb8a2fa49eeab",
        "Signer #1 certificate SHA-1 digest: b21ed33311d34d0777e97b467ba7528878946f13"
    )
    Assert-Equal -Actual $parsedApkHashes.SHA1 -Expected "b21ed33311d34d0777e97b467ba7528878946f13" -Message "Failed to parse apksigner SHA-1 output."
    Assert-Equal -Actual $parsedApkHashes.SHA256 -Expected "3d799ffef509df0766fb9d1cc6ac22914ecef5678b69d6224d0cb8a2fa49eeab" -Message "Failed to parse apksigner SHA-256 output."

    Write-Output "release_common tests passed."
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
