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

function Invoke-NativeCommandCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $FilePath @Arguments 2>&1
        $nativeExitCode = $LASTEXITCODE

        if ($nativeExitCode -ne 0) {
            $joinedArguments = if ($Arguments.Count -gt 0) {
                $Arguments -join " "
            } else {
                ""
            }
            $details = @($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
            throw "Command failed with exit code ${nativeExitCode}: $FilePath $joinedArguments`n$details".TrimEnd()
        }

        return @($output | ForEach-Object { "$_" })
    } finally {
        $ErrorActionPreference = $previousPreference
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

function Get-KeyValueProperties {
    param([Parameter(Mandatory = $true)][string]$Path)

    $properties = @{}
    foreach ($line in Get-Content -Path $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
            continue
        }

        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $properties[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $properties
}

function Resolve-FileAgainstBaseDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $BaseDirectory $Path
}

function Get-AndroidSigningInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $requiredKeys = @("storeFile", "storePassword", "keyAlias", "keyPassword")

    if (-not (Test-Path $Path)) {
        return [PSCustomObject]@{
            Mode = "DEBUG"
            Warning = "android/key.properties was not found. Android release builds require the production keystore."
        }
    }

    $properties = Get-KeyValueProperties -Path $Path
    $missingKeys = @($requiredKeys | Where-Object {
        -not $properties.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($properties[$_])
    })

    if ($missingKeys.Count -gt 0) {
        return [PSCustomObject]@{
            Mode = "DEBUG"
            Warning = "android/key.properties is missing required values ($($missingKeys -join ', ')). Android release builds require the production keystore."
        }
    }

    $storeFilePath = Resolve-FileAgainstBaseDirectory `
        -BaseDirectory (Split-Path $Path -Parent) `
        -Path $properties["storeFile"]

    if (-not (Test-Path $storeFilePath)) {
        return [PSCustomObject]@{
            Mode = "DEBUG"
            Warning = "android/key.properties points to a missing keystore file: $storeFilePath"
        }
    }

    return [PSCustomObject]@{
        Mode = "RELEASE"
        Warning = $null
        StoreFilePath = (Resolve-Path $storeFilePath).Path
        StorePassword = $properties["storePassword"]
        KeyAlias = $properties["keyAlias"]
        KeyPassword = $properties["keyPassword"]
    }
}

function Get-AndroidVersionInfo {
    param([Parameter(Mandatory = $true)][string]$PubspecPath)

    $pubspec = Get-Content -Path $PubspecPath -Raw
    if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
        return [PSCustomObject]@{
            VersionName = $matches[1]
            VersionCode = [int]$matches[2]
        }
    }

    if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$') {
        throw "Android releases require pubspec.yaml version in X.Y.Z+N format so versionCode stays monotonic. Example: 1.2.3+4."
    }

    throw "Could not parse Android version info from $PubspecPath"
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

function Normalize-CertificateHash {
    param([Parameter(Mandatory = $true)][string]$Value)

    return ($Value -replace '[^0-9A-Fa-f]', '').ToLowerInvariant()
}

function Get-CertificateHashesFromText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $text = $Lines -join "`n"
    $sha1 = $null
    $sha256 = $null

    foreach ($pattern in @(
        'SHA1:\s*([0-9A-Fa-f:]+)',
        'SHA-1 digest:\s*([0-9A-Fa-f:]+)'
    )) {
        if ($text -match $pattern) {
            $sha1 = Normalize-CertificateHash -Value $matches[1]
            break
        }
    }

    foreach ($pattern in @(
        'SHA256:\s*([0-9A-Fa-f:]+)',
        'SHA-256 digest:\s*([0-9A-Fa-f:]+)'
    )) {
        if ($text -match $pattern) {
            $sha256 = Normalize-CertificateHash -Value $matches[1]
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($sha1) -or [string]::IsNullOrWhiteSpace($sha256)) {
        throw "Could not parse certificate hashes from native tool output."
    }

    return [PSCustomObject]@{
        SHA1 = $sha1
        SHA256 = $sha256
    }
}

function Get-KeytoolPath {
    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin\\keytool.exe"))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates.Add((Join-Path $env:ProgramFiles "Android\\Android Studio\\jbr\\bin\\keytool.exe"))
        $candidates.Add((Join-Path $env:ProgramFiles "Android\\Android Studio\\jre\\bin\\keytool.exe"))

        $javaRoot = Join-Path $env:ProgramFiles "Java"
        if (Test-Path $javaRoot) {
            foreach ($directory in Get-ChildItem -Path $javaRoot -Directory -ErrorAction SilentlyContinue) {
                $candidates.Add((Join-Path $directory.FullName "bin\\keytool.exe"))
            }
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw "Could not find keytool. Install a JDK or set JAVA_HOME before building Android releases."
}

function Get-ApkSignerPath {
    $sdkRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path $root)) {
            $sdkRoots.Add($root)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $defaultSdkRoot = Join-Path $env:LOCALAPPDATA "Android\\Sdk"
        if (Test-Path $defaultSdkRoot) {
            $sdkRoots.Add($defaultSdkRoot)
        }
    }

    foreach ($sdkRoot in $sdkRoots | Select-Object -Unique) {
        $buildToolsRoot = Join-Path $sdkRoot "build-tools"
        if (-not (Test-Path $buildToolsRoot)) {
            continue
        }

        $buildToolsDirectories = Get-ChildItem -Path $buildToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object {
                try {
                    [version]$_.Name
                } catch {
                    [version]"0.0.0.0"
                }
            } -Descending

        foreach ($directory in $buildToolsDirectories) {
            foreach ($candidateName in @("apksigner.bat", "apksigner.exe")) {
                $candidate = Join-Path $directory.FullName $candidateName
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }

    throw "Could not find apksigner in the Android SDK build-tools. Install Android build-tools before building Android releases."
}

function Get-KeystoreCertificateHashes {
    param(
        [Parameter(Mandatory = $true)][string]$StoreFilePath,
        [Parameter(Mandatory = $true)][string]$StorePassword,
        [Parameter(Mandatory = $true)][string]$KeyAlias,
        [Parameter(Mandatory = $true)][string]$KeyPassword
    )

    $keytoolPath = Get-KeytoolPath
    $output = Invoke-NativeCommandCapture -FilePath $keytoolPath -Arguments @(
        "-list",
        "-v",
        "-keystore",
        $StoreFilePath,
        "-alias",
        $KeyAlias,
        "-storepass",
        $StorePassword,
        "-keypass",
        $KeyPassword
    )

    return Get-CertificateHashesFromText -Lines $output
}

function Get-ApkCertificateHashes {
    param([Parameter(Mandatory = $true)][string]$ApkPath)

    $apksignerPath = Get-ApkSignerPath
    $output = Invoke-NativeCommandCapture -FilePath $apksignerPath -Arguments @(
        "verify",
        "--print-certs",
        $ApkPath
    )

    return Get-CertificateHashesFromText -Lines $output
}

function Get-GoogleServicesAndroidCertificateHashes {
    param(
        [Parameter(Mandatory = $true)][string]$GoogleServicesJsonPath,
        [string]$PackageName = ""
    )

    if (-not (Test-Path $GoogleServicesJsonPath)) {
        throw "Missing $GoogleServicesJsonPath. Download it from Firebase before building Android releases."
    }

    $json = Get-Content -Path $GoogleServicesJsonPath -Raw | ConvertFrom-Json
    $hashes = [System.Collections.Generic.List[string]]::new()

    foreach ($client in @($json.client)) {
        $configuredPackageName = [string]$client.client_info.android_client_info.package_name
        if (-not [string]::IsNullOrWhiteSpace($PackageName) -and $configuredPackageName -ne $PackageName) {
            continue
        }

        foreach ($oauthClient in @($client.oauth_client)) {
            if ($oauthClient.client_type -ne 1 -or $null -eq $oauthClient.android_info) {
                continue
            }

            $oauthPackageName = [string]$oauthClient.android_info.package_name
            if (-not [string]::IsNullOrWhiteSpace($PackageName) -and $oauthPackageName -ne $PackageName) {
                continue
            }

            $certificateHash = [string]$oauthClient.android_info.certificate_hash
            if (-not [string]::IsNullOrWhiteSpace($certificateHash)) {
                $hashes.Add((Normalize-CertificateHash -Value $certificateHash))
            }
        }
    }

    return $hashes | Sort-Object -Unique
}

function Assert-ReleaseCertificateRegistered {
    param(
        [Parameter(Mandatory = $true)][string]$GoogleServicesJsonPath,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$ReleaseCertificateSha1
    )

    $registeredHashes = @(Get-GoogleServicesAndroidCertificateHashes `
        -GoogleServicesJsonPath $GoogleServicesJsonPath `
        -PackageName $PackageName)
    $normalizedReleaseHash = Normalize-CertificateHash -Value $ReleaseCertificateSha1

    if ($registeredHashes -notcontains $normalizedReleaseHash) {
        throw "android/app/google-services.json does not contain the production SHA-1 '$normalizedReleaseHash' for $PackageName. Add the release fingerprint in Firebase Console and re-download google-services.json before building."
    }
}
