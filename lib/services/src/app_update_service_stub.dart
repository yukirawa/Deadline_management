import 'package:kigenkanri/models/app_update_info.dart';

typedef DownloadProgressCallback = void Function(double progress);

class File {
  File(this.path);

  final String path;
  String _contents = '';

  Future<bool> exists() async => false;

  Future<String> readAsString() async => _contents;

  Future<void> writeAsString(String contents) async {
    _contents = contents;
  }
}

class AppUpdateService {
  AppUpdateService({
    Object? httpClient,
    Future<String> Function()? currentVersionProvider,
    Future<Object?> Function()? temporaryDirectoryProvider,
    bool? supportsOtaUpdates,
    Duration? requestTimeout,
    Duration? downloadTimeout,
    Uri? latestReleaseUri,
    Uri? latestApkUri,
  });

  Future<void> cleanupCachedApkFiles() async {}

  Future<AppUpdateInfo?> checkForUpdate() async => null;

  Future<File> downloadLatestApk(
    AppUpdateInfo info,
    DownloadProgressCallback onProgress,
  ) {
    throw UnsupportedError(
      'Android OTA updates are unavailable on this platform.',
    );
  }
}
