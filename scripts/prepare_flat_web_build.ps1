param(
    [Parameter(Mandatory = $true)][string]$WebBuildDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-FlatWebAssetName {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalizedRelativePath = $RelativePath.Replace("\", "/").TrimStart("/")
    return "__flat__" + ($normalizedRelativePath -replace "/", "__")
}

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $resolvedBasePath = (Resolve-Path $BasePath).Path
    if (-not $resolvedBasePath.EndsWith("\")) {
        $resolvedBasePath += "\"
    }

    $baseUri = [Uri]$resolvedBasePath
    $targetUri = [Uri](Resolve-Path $TargetPath).Path
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace("\", "/")
}

function Copy-FlattenedDirectoryFiles {
    param(
        [Parameter(Mandatory = $true)][string]$WebBuildDir,
        [Parameter(Mandatory = $true)][string]$RelativeDirectory
    )

    $sourceDirectory = Join-Path $WebBuildDir $RelativeDirectory
    $copiedFiles = @{}

    if (-not (Test-Path $sourceDirectory)) {
        return $copiedFiles
    }

    foreach ($file in Get-ChildItem -Path $sourceDirectory -File -Recurse) {
        $relativeFilePath = Get-NormalizedRelativePath -BasePath $WebBuildDir -TargetPath $file.FullName
        $flatFileName = Get-FlatWebAssetName -RelativePath $relativeFilePath
        $destinationPath = Join-Path $WebBuildDir $flatFileName
        Copy-Item -Path $file.FullName -Destination $destinationPath -Force
        $copiedFiles[$relativeFilePath] = $flatFileName
    }

    return $copiedFiles
}

function Copy-CanvasKitFilesToRoot {
    param([Parameter(Mandatory = $true)][string]$WebBuildDir)

    $canvasKitDirectory = Join-Path $WebBuildDir "canvaskit"
    if (-not (Test-Path $canvasKitDirectory)) {
        return
    }

    foreach ($file in Get-ChildItem -Path $canvasKitDirectory -File) {
        Copy-Item -Path $file.FullName -Destination (Join-Path $WebBuildDir $file.Name) -Force
    }
}

function Update-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$Transform
    )

    $originalContent = Get-Content -Path $Path -Raw
    $updatedContent = & $Transform $originalContent
    if ($updatedContent -ne $originalContent) {
        Set-Content -Path $Path -Value $updatedContent -NoNewline
    }
}

if (-not (Test-Path $WebBuildDir)) {
    throw "Web build directory '$WebBuildDir' was not found."
}

$assetFileMap = @{}
foreach ($directory in @("assets", "icons")) {
    foreach ($entry in (Copy-FlattenedDirectoryFiles -WebBuildDir $WebBuildDir -RelativeDirectory $directory).GetEnumerator()) {
        $assetFileMap[$entry.Key] = $entry.Value
    }
}

Copy-CanvasKitFilesToRoot -WebBuildDir $WebBuildDir

$indexPath = Join-Path $WebBuildDir "index.html"
$manifestPath = Join-Path $WebBuildDir "manifest.json"
$firebaseMessagingServiceWorkerPath = Join-Path $WebBuildDir "firebase-messaging-sw.js"
$flutterBootstrapPath = Join-Path $WebBuildDir "flutter_bootstrap.js"

$flatAssetRewriteScript = @'
  <script>
    (() => {
      const baseHref = document.querySelector('base')?.getAttribute('href') ?? '/';
      const baseUrl = new URL(baseHref, window.location.origin);
      const flattenablePrefixes = ['assets/', 'icons/'];

      const getFlattenedUrl = (value) => {
        const resolved = new URL(String(value), baseUrl);
        if (resolved.origin !== baseUrl.origin) {
          return null;
        }

        const basePath = baseUrl.pathname.endsWith('/') ? baseUrl.pathname : `${baseUrl.pathname}/`;
        if (!resolved.pathname.startsWith(basePath)) {
          return null;
        }

        const relativePath = resolved.pathname.slice(basePath.length);
        if (!flattenablePrefixes.some((prefix) => relativePath.startsWith(prefix))) {
          return null;
        }

        const flatFileName = `__flat__${relativePath.split('/').join('__')}`;
        return new URL(flatFileName + resolved.search + resolved.hash, baseUrl).toString();
      };

      const rewriteValue = (value) => {
        if (typeof value !== 'string' && !(value instanceof URL)) {
          return value;
        }
        return getFlattenedUrl(value) ?? value;
      };

      const nativeFetch = window.fetch?.bind(window);
      if (nativeFetch) {
        window.fetch = (input, init) => {
          if (typeof Request !== 'undefined' && input instanceof Request) {
            const rewrittenUrl = getFlattenedUrl(input.url);
            if (rewrittenUrl) {
              return nativeFetch(new Request(rewrittenUrl, input), init);
            }
            return nativeFetch(input, init);
          }

          return nativeFetch(rewriteValue(input), init);
        };
      }

      const nativeOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        return nativeOpen.call(this, method, rewriteValue(url), ...rest);
      };
    })();
  </script>
'@

if (Test-Path $indexPath) {
    Update-TextFile -Path $indexPath -Transform {
        param($content)

        foreach ($entry in $assetFileMap.GetEnumerator()) {
            $content = $content.Replace($entry.Key, $entry.Value)
        }

        if (-not $content.Contains("__flat__assets__AssetManifest.bin.json")) {
            $content = $content.Replace(
                '<script src="flutter_bootstrap.js" async></script>',
                "$flatAssetRewriteScript`r`n  <script src=""flutter_bootstrap.js"" async></script>"
            )
        }

        return $content
    }
}

if (Test-Path $manifestPath) {
    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.icons) {
        foreach ($icon in $manifest.icons) {
            if ($assetFileMap.ContainsKey($icon.src)) {
                $icon.src = $assetFileMap[$icon.src]
            }
        }
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -NoNewline
}

if (Test-Path $firebaseMessagingServiceWorkerPath) {
    Update-TextFile -Path $firebaseMessagingServiceWorkerPath -Transform {
        param($content)

        foreach ($entry in $assetFileMap.GetEnumerator()) {
            $content = $content.Replace($entry.Key, $entry.Value)
        }

        return $content
    }
}

if (Test-Path $flutterBootstrapPath) {
    Update-TextFile -Path $flutterBootstrapPath -Transform {
        param($content)

        $replacement = @'
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: ".",
    canvasKitVariant: "full"
  }
});
'@

        return [regex]::Replace(
            $content,
            '(?s)_flutter\.loader\.load\(\{.*?\}\);\s*$',
            $replacement
        )
    }
}
