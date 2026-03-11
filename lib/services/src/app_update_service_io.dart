import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kigenkanri/models/app_update_info.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

typedef DownloadProgressCallback = void Function(double progress);
typedef PackageVersionProvider = Future<String> Function();
typedef TemporaryDirectoryProvider = Future<Directory> Function();

class AppUpdateService {
  AppUpdateService({
    http.Client? httpClient,
    PackageVersionProvider? currentVersionProvider,
    TemporaryDirectoryProvider? temporaryDirectoryProvider,
    bool? supportsOtaUpdates,
    Duration? requestTimeout,
    Duration? downloadTimeout,
    Uri? latestReleaseUri,
    Uri? latestApkUri,
  }) : _httpClient = httpClient ?? http.Client(),
       _currentVersionProvider =
           currentVersionProvider ?? _defaultCurrentVersionProvider,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _supportsOtaUpdates = supportsOtaUpdates ?? Platform.isAndroid,
       _requestTimeout = requestTimeout ?? const Duration(seconds: 5),
       _downloadTimeout = downloadTimeout ?? const Duration(minutes: 2),
       _latestReleaseUri = latestReleaseUri ?? _defaultLatestReleaseUri,
       _latestApkUri = latestApkUri ?? _defaultLatestApkUri;

  final http.Client _httpClient;
  final PackageVersionProvider _currentVersionProvider;
  final TemporaryDirectoryProvider _temporaryDirectoryProvider;
  final bool _supportsOtaUpdates;
  final Duration _requestTimeout;
  final Duration _downloadTimeout;
  final Uri _latestReleaseUri;
  final Uri _latestApkUri;

  Future<void> cleanupCachedApkFiles() async {
    if (!_supportsOtaUpdates) {
      return;
    }

    final directory = await _temporaryDirectoryProvider();
    if (!await directory.exists()) {
      return;
    }

    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final fileName = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (!fileName.startsWith(_cachedApkPrefix) ||
          !fileName.endsWith(_cachedApkSuffix)) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {
        // Ignore cleanup failures and keep startup resilient.
      }
    }
  }

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (!_supportsOtaUpdates) {
      return null;
    }

    try {
      await cleanupCachedApkFiles();

      final currentVersion = SemanticVersion.tryParse(
        await _currentVersionProvider(),
      );
      if (currentVersion == null) {
        return null;
      }

      final releaseTag = await _fetchLatestReleaseTag();
      if (releaseTag == null) {
        return null;
      }

      final latestVersion = SemanticVersion.fromReleaseTag(releaseTag);
      if (latestVersion == null ||
          latestVersion.compareTo(currentVersion) <= 0) {
        return null;
      }

      final assetExists = await _preflightLatestApk();
      if (!assetExists) {
        return null;
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseTag: releaseTag,
        releasePageUrl: _latestReleaseUri.resolve(
          '/yukirawa/Deadline_management/releases/tag/$releaseTag',
        ),
        apkUrl: _latestApkUri,
      );
    } catch (_) {
      return null;
    }
  }

  Future<File> downloadLatestApk(
    AppUpdateInfo info,
    DownloadProgressCallback onProgress,
  ) async {
    if (!_supportsOtaUpdates) {
      throw UnsupportedError(
        'Android OTA updates are unavailable on this platform.',
      );
    }

    final directory = await _temporaryDirectoryProvider();
    await directory.create(recursive: true);

    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      '$_cachedApkPrefix${info.latestVersion}$_cachedApkSuffix',
    );
    await _deleteCachedApkFilesExcept(directory, target.path);

    final request = http.Request('GET', info.apkUrl);
    final response = await _httpClient.send(request).timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('APK download failed with HTTP ${response.statusCode}.');
    }

    if (await target.exists()) {
      await target.delete();
    }

    final sink = target.openWrite();
    final totalBytes = response.contentLength;
    var receivedBytes = 0;
    var sentIndeterminateProgress = false;

    try {
      if (totalBytes == null || totalBytes <= 0) {
        sentIndeterminateProgress = true;
        onProgress(-1);
      } else {
        onProgress(0);
      }

      await for (final chunk in response.stream.timeout(_downloadTimeout)) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (!sentIndeterminateProgress &&
            totalBytes != null &&
            totalBytes > 0) {
          final ratio = receivedBytes / totalBytes;
          onProgress(ratio.clamp(0, 1).toDouble());
        }
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await target.exists()) {
        await target.delete();
      }
      rethrow;
    }

    await sink.close();
    onProgress(1);
    return target;
  }

  Future<String?> _fetchLatestReleaseTag() async {
    final request = http.Request('GET', _latestReleaseUri)
      ..followRedirects = false
      ..maxRedirects = 0;
    final response = await _httpClient.send(request).timeout(_requestTimeout);
    await response.stream.drain();

    if (response.statusCode < 300 || response.statusCode >= 400) {
      return null;
    }

    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      return null;
    }

    final redirectedUri = _latestReleaseUri.resolve(location);
    final segments = redirectedUri.pathSegments;
    if (segments.length < 5 ||
        segments[0] != 'yukirawa' ||
        segments[1] != 'Deadline_management' ||
        segments[2] != 'releases' ||
        segments[3] != 'tag') {
      return null;
    }

    return segments[4];
  }

  Future<bool> _preflightLatestApk() async {
    final request = http.Request('GET', _latestApkUri)
      ..followRedirects = false
      ..maxRedirects = 0;
    final response = await _httpClient.send(request).timeout(_requestTimeout);
    await response.stream.drain();
    return response.statusCode >= 200 && response.statusCode < 400;
  }

  Future<void> _deleteCachedApkFilesExcept(
    Directory directory,
    String keepPath,
  ) async {
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final fileName = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (!fileName.startsWith(_cachedApkPrefix) ||
          !fileName.endsWith(_cachedApkSuffix) ||
          entity.path == keepPath) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {
        // Ignore stale file cleanup errors and keep the fresh download.
      }
    }
  }

  static Future<String> _defaultCurrentVersionProvider() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }
}

final Uri _defaultLatestReleaseUri = Uri.https(
  'github.com',
  '/yukirawa/Deadline_management/releases/latest',
);
final Uri _defaultLatestApkUri = Uri.https(
  'github.com',
  '/yukirawa/Deadline_management/releases/latest/download/app-release.apk',
);
const String _cachedApkPrefix = 'update-';
const String _cachedApkSuffix = '.apk';
