import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kigenkanri/models/app_update_info.dart';
import 'package:kigenkanri/services/android_apk_installer.dart';
import 'package:kigenkanri/services/app_update_service.dart';

class AppBootstrapPage extends StatefulWidget {
  AppBootstrapPage({
    super.key,
    required this.child,
    AppUpdateService? appUpdateService,
    AndroidApkInstaller? apkInstaller,
  }) : appUpdateService = appUpdateService ?? AppUpdateService(),
       apkInstaller = apkInstaller ?? AndroidApkInstaller();

  final Widget child;
  final AppUpdateService appUpdateService;
  final AndroidApkInstaller apkInstaller;

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage>
    with WidgetsBindingObserver {
  final ValueNotifier<double> _downloadProgress = ValueNotifier<double>(0);

  bool _hasCheckedForUpdate = false;
  bool _isUpdateDialogVisible = false;
  bool _isProgressDialogVisible = false;
  bool _resumePermissionCheckPending = false;
  bool _sessionDismissed = false;
  String? _pendingInstallPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdateOnce());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _downloadProgress.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _resumePermissionCheckPending) {
      _resumePermissionCheckPending = false;
      unawaited(_resumePendingInstallIfNeeded());
    }
  }

  Future<void> _checkForUpdateOnce() async {
    if (_hasCheckedForUpdate) {
      return;
    }
    _hasCheckedForUpdate = true;

    AppUpdateInfo? updateInfo;
    try {
      updateInfo = await widget.appUpdateService.checkForUpdate();
    } catch (_) {
      return;
    }

    if (!mounted ||
        updateInfo == null ||
        _sessionDismissed ||
        _pendingInstallPath != null) {
      return;
    }

    if (_requiresManualReinstall(updateInfo)) {
      await _showManualReinstallPrompt(updateInfo);
      return;
    }

    await _showUpdatePrompt(updateInfo);
  }

  bool _requiresManualReinstall(AppUpdateInfo updateInfo) {
    return updateInfo.currentVersion.compareTo(_manualReinstallCutoffVersion) <
        0;
  }

  Future<void> _showManualReinstallPrompt(AppUpdateInfo updateInfo) async {
    if (!mounted || _isUpdateDialogVisible) {
      return;
    }

    _isUpdateDialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('手動更新が必要です'),
          content: Text(
            'このアプリは 2026-03-12 より前の署名でインストールされているため、'
            '今回の更新はアプリ内アップデートでは適用できません。\n\n'
            'GitHub Releases から最新版 APK をダウンロードして'
            '一度だけ手動で再インストールしてください。\n\n'
            '配布ページ:\n${updateInfo.releasePageUrl}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
    _isUpdateDialogVisible = false;
    _sessionDismissed = true;
  }

  Future<void> _showUpdatePrompt(AppUpdateInfo updateInfo) async {
    if (!mounted || _isUpdateDialogVisible) {
      return;
    }

    _isUpdateDialogVisible = true;
    final action = await showDialog<_UpdateAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('新しいバージョンがあります'),
          content: Text(
            '現在のバージョン: ${updateInfo.currentVersion}\n'
            '最新のバージョン: ${updateInfo.latestVersion}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_UpdateAction.later),
              child: const Text('あとで'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_UpdateAction.updateNow),
              child: const Text('更新する'),
            ),
          ],
        );
      },
    );
    _isUpdateDialogVisible = false;

    if (!mounted || action == null || action == _UpdateAction.later) {
      _sessionDismissed = true;
      return;
    }

    await _downloadAndInstall(updateInfo);
  }

  Future<void> _downloadAndInstall(AppUpdateInfo updateInfo) async {
    _downloadProgress.value = 0;
    _showProgressDialog();

    try {
      final apkFile = await widget.appUpdateService.downloadLatestApk(
        updateInfo,
        (progress) => _downloadProgress.value = progress,
      );
      _pendingInstallPath = apkFile.path;

      final permission = await widget.apkInstaller.ensureInstallPermission();
      switch (permission) {
        case InstallPermissionResult.granted:
          await _installPendingApk();
          return;
        case InstallPermissionResult.needsSettings:
          _resumePermissionCheckPending = true;
          return;
        case InstallPermissionResult.unavailable:
          throw StateError('この端末ではアプリ更新を開始できません。');
      }
    } catch (error) {
      _pendingInstallPath = null;
      _closeProgressDialog();
      _showError('更新に失敗しました: $error');
    }
  }

  Future<void> _resumePendingInstallIfNeeded() async {
    if (!mounted || _pendingInstallPath == null) {
      return;
    }

    try {
      final status = await widget.apkInstaller.getInstallPermissionStatus();
      if (status == InstallPermissionResult.granted) {
        await _installPendingApk();
        return;
      }

      _pendingInstallPath = null;
      _closeProgressDialog();
      _showError('提供元不明のアプリの許可が必要です。');
    } catch (error) {
      _pendingInstallPath = null;
      _closeProgressDialog();
      _showError('更新を再開できませんでした: $error');
    }
  }

  Future<void> _installPendingApk() async {
    final installPath = _pendingInstallPath;
    if (installPath == null) {
      return;
    }

    try {
      await widget.apkInstaller.installApk(installPath);
      _pendingInstallPath = null;
      _closeProgressDialog();
    } catch (error) {
      _pendingInstallPath = null;
      _closeProgressDialog();
      _showError('インストーラーを起動できませんでした: $error');
    }
  }

  void _showProgressDialog() {
    if (!mounted || _isProgressDialogVisible) {
      return;
    }

    _isProgressDialogVisible = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('アップデートを準備しています'),
            content: ValueListenableBuilder<double>(
              valueListenable: _downloadProgress,
              builder: (context, progress, _) {
                final isIndeterminate = progress < 0 || progress.isNaN;
                final progressValue = isIndeterminate ? null : progress;
                final progressText = isIndeterminate
                    ? 'ダウンロード中...'
                    : 'ダウンロード中... ${(progress * 100).round()}%';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: progressValue),
                    const SizedBox(height: 12),
                    Text(progressText),
                  ],
                );
              },
            ),
          );
        },
      ).whenComplete(() {
        _isProgressDialogVisible = false;
      }),
    );
  }

  void _closeProgressDialog() {
    if (!mounted || !_isProgressDialogVisible) {
      return;
    }

    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

enum _UpdateAction { later, updateNow }

final SemanticVersion _manualReinstallCutoffVersion = SemanticVersion.parse(
  '1.2.2',
);
