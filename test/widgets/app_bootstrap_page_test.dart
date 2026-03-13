import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/models/app_update_info.dart';
import 'package:kigenkanri/screens/app_bootstrap_page.dart';
import 'package:kigenkanri/services/android_apk_installer.dart';
import 'package:kigenkanri/services/app_update_service.dart';

void main() {
  AppUpdateInfo buildUpdateInfoWithVersions({
    required String current,
    required String latest,
  }) {
    return AppUpdateInfo(
      currentVersion: SemanticVersion.parse(current),
      latestVersion: SemanticVersion.parse(latest),
      releaseTag: 'v$latest',
      releasePageUrl: Uri.parse(
        'https://github.com/yukirawa/Deadline_management/releases/tag/v$latest',
      ),
      apkUrl: Uri.parse(
        'https://github.com/yukirawa/Deadline_management/releases/latest/download/app-release.apk',
      ),
    );
  }

  AppUpdateInfo buildUpdateInfo() {
    return buildUpdateInfoWithVersions(current: '1.2.2', latest: '1.2.3');
  }

  Widget buildSubject({
    required AppUpdateService appUpdateService,
    required AndroidApkInstaller apkInstaller,
  }) {
    return MaterialApp(
      home: AppBootstrapPage(
        appUpdateService: appUpdateService,
        apkInstaller: apkInstaller,
        child: const Scaffold(body: Text('child home')),
      ),
    );
  }

  testWidgets('new release prompt is shown once and later dismisses it', (
    WidgetTester tester,
  ) async {
    final service = FakeAppUpdateService(updateInfo: buildUpdateInfo());
    final installer = FakeAndroidApkInstaller();

    await tester.pumpWidget(
      buildSubject(appUpdateService: service, apkInstaller: installer),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('新しいバージョンがあります'), findsOneWidget);
    expect(service.checkCount, 1);

    await tester.tap(find.text('あとで'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新しいバージョンがあります'), findsNothing);
    expect(find.text('child home'), findsOneWidget);
    expect(service.checkCount, 1);
  });

  testWidgets('update now opens the progress dialog', (
    WidgetTester tester,
  ) async {
    final downloadCompleter = Completer<File>();
    final service = FakeAppUpdateService(
      updateInfo: buildUpdateInfo(),
      downloadAction: (_, onProgress) {
        onProgress(0.25);
        return downloadCompleter.future;
      },
    );
    final installer = FakeAndroidApkInstaller();

    await tester.pumpWidget(
      buildSubject(appUpdateService: service, apkInstaller: installer),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('更新する'));
    await tester.pump();

    expect(find.text('アップデートを準備しています'), findsOneWidget);
    expect(find.textContaining('25%'), findsOneWidget);
  });

  testWidgets('legacy signed installs show a manual reinstall prompt', (
    WidgetTester tester,
  ) async {
    final service = FakeAppUpdateService(
      updateInfo: buildUpdateInfoWithVersions(
        current: '1.2.1',
        latest: '1.2.3',
      ),
    );
    final installer = FakeAndroidApkInstaller();

    await tester.pumpWidget(
      buildSubject(appUpdateService: service, apkInstaller: installer),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('手動更新が必要です'), findsOneWidget);
    expect(find.textContaining('GitHub Releases'), findsOneWidget);
    expect(find.textContaining('v1.2.3'), findsOneWidget);
    expect(installer.installedPaths, isEmpty);
  });

  testWidgets('update check failures do not block normal startup', (
    WidgetTester tester,
  ) async {
    final service = FakeAppUpdateService(
      checkAction: () => throw Exception('network failure'),
    );
    final installer = FakeAndroidApkInstaller();

    await tester.pumpWidget(
      buildSubject(appUpdateService: service, apkInstaller: installer),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('child home'), findsOneWidget);
    expect(find.text('新しいバージョンがあります'), findsNothing);
  });
}

class FakeAppUpdateService extends AppUpdateService {
  FakeAppUpdateService({
    this.updateInfo,
    this.checkAction,
    this.downloadAction,
  });

  final AppUpdateInfo? updateInfo;
  final Future<AppUpdateInfo?> Function()? checkAction;
  final Future<File> Function(
    AppUpdateInfo info,
    DownloadProgressCallback onProgress,
  )?
  downloadAction;
  int checkCount = 0;

  @override
  Future<AppUpdateInfo?> checkForUpdate() async {
    checkCount += 1;
    if (checkAction != null) {
      return checkAction!();
    }
    return updateInfo;
  }

  @override
  Future<File> downloadLatestApk(
    AppUpdateInfo info,
    DownloadProgressCallback onProgress,
  ) async {
    if (downloadAction != null) {
      return downloadAction!(info, onProgress);
    }

    final file = File('${Directory.systemTemp.path}/fake-update.apk');
    await file.writeAsString('apk');
    onProgress(1);
    return file;
  }
}

class FakeAndroidApkInstaller extends AndroidApkInstaller {
  FakeAndroidApkInstaller({
    this.ensureResult = InstallPermissionResult.granted,
    this.statusResult = InstallPermissionResult.granted,
  });

  final InstallPermissionResult ensureResult;
  final InstallPermissionResult statusResult;
  final List<String> installedPaths = <String>[];

  @override
  Future<InstallPermissionResult> ensureInstallPermission() async {
    return ensureResult;
  }

  @override
  Future<InstallPermissionResult> getInstallPermissionStatus() async {
    return statusResult;
  }

  @override
  Future<void> installApk(String filePath) async {
    installedPaths.add(filePath);
  }
}
