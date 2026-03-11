import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum InstallPermissionResult { granted, needsSettings, unavailable }

class AndroidApkInstaller {
  AndroidApkInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  Future<InstallPermissionResult> getInstallPermissionStatus() async {
    if (!_isSupportedPlatform) {
      return InstallPermissionResult.unavailable;
    }

    final isGranted =
        await _channel.invokeMethod<bool>('canRequestPackageInstalls') ?? false;
    return isGranted
        ? InstallPermissionResult.granted
        : InstallPermissionResult.needsSettings;
  }

  Future<InstallPermissionResult> ensureInstallPermission() async {
    final status = await getInstallPermissionStatus();
    if (status != InstallPermissionResult.needsSettings) {
      return status;
    }

    final openedSettings =
        await _channel.invokeMethod<bool>('openInstallPermissionSettings') ??
        false;
    return openedSettings
        ? InstallPermissionResult.needsSettings
        : InstallPermissionResult.unavailable;
  }

  Future<void> installApk(String filePath) async {
    if (!_isSupportedPlatform) {
      throw UnsupportedError(
        'APK installation is unavailable on this platform.',
      );
    }

    await _channel.invokeMethod<void>('installApk', {'filePath': filePath});
  }

  bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

const String _channelName = 'jp.yukirawa.kigenkanri/app_updater';
