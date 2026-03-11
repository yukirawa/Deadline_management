import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kigenkanri/models/app_update_info.dart';
import 'package:kigenkanri/services/app_update_service.dart';

void main() {
  group('SemanticVersion', () {
    test('strict semver and release tag parsing works', () {
      expect(SemanticVersion.parse('1.2.3').toString(), '1.2.3');
      expect(SemanticVersion.fromReleaseTag('v1.2.3')?.toString(), '1.2.3');
      expect(SemanticVersion.fromReleaseTag('v1.2'), isNull);
      expect(SemanticVersion.tryParse('1.2'), isNull);
    });

    test('newer versions compare higher', () {
      final current = SemanticVersion.parse('1.1.0');
      final latest = SemanticVersion.parse('1.2.0');

      expect(latest.compareTo(current), greaterThan(0));
      expect(current.compareTo(current), 0);
      expect(current.compareTo(latest), lessThan(0));
    });

    test('major and patch increments also compare correctly', () {
      final patchCurrent = SemanticVersion.parse('1.1.0');
      final patchLatest = SemanticVersion.parse('1.1.1');
      final majorCurrent = SemanticVersion.parse('1.9.9');
      final majorLatest = SemanticVersion.parse('2.0.0');

      expect(patchLatest.compareTo(patchCurrent), greaterThan(0));
      expect(majorLatest.compareTo(majorCurrent), greaterThan(0));
    });
  });

  group('AppUpdateService.checkForUpdate', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app-update-test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'returns update info when latest redirect and APK asset are valid',
      () async {
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    'https://github.com/yukirawa/Deadline_management/releases/tag/v1.1.1',
              },
            );
          }
          if (request.url.path.endsWith(
            '/releases/latest/download/app-release.apk',
          )) {
            return http.Response('', 302);
          }
          throw StateError('Unexpected URL: ${request.url}');
        });

        final service = AppUpdateService(
          httpClient: client,
          currentVersionProvider: () async => '1.1.0',
          temporaryDirectoryProvider: () async => tempDir,
          supportsOtaUpdates: true,
        );

        final info = await service.checkForUpdate();

        expect(info, isNotNull);
        expect(info?.releaseTag, 'v1.1.1');
        expect(info?.currentVersion.toString(), '1.1.0');
        expect(info?.latestVersion.toString(), '1.1.1');
      },
    );

    test('returns null when latest tag is not strict semver', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://github.com/yukirawa/Deadline_management/releases/tag/v1.0',
            },
          );
        }
        if (request.url.path.endsWith(
          '/releases/latest/download/app-release.apk',
        )) {
          return http.Response('', 302);
        }
        throw StateError('Unexpected URL: ${request.url}');
      });

      final service = AppUpdateService(
        httpClient: client,
        currentVersionProvider: () async => '1.1.0',
        temporaryDirectoryProvider: () async => tempDir,
        supportsOtaUpdates: true,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when APK preflight fails', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://github.com/yukirawa/Deadline_management/releases/tag/v1.1.1',
            },
          );
        }
        if (request.url.path.endsWith(
          '/releases/latest/download/app-release.apk',
        )) {
          return http.Response('', 404);
        }
        throw StateError('Unexpected URL: ${request.url}');
      });

      final service = AppUpdateService(
        httpClient: client,
        currentVersionProvider: () async => '1.1.0',
        temporaryDirectoryProvider: () async => tempDir,
        supportsOtaUpdates: true,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when release lookup times out', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('', 302);
      });

      final service = AppUpdateService(
        httpClient: client,
        currentVersionProvider: () async => '1.1.0',
        temporaryDirectoryProvider: () async => tempDir,
        supportsOtaUpdates: true,
        requestTimeout: const Duration(milliseconds: 10),
      );

      expect(await service.checkForUpdate(), isNull);
    });
  });

  group('AppUpdateService.downloadLatestApk', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app-update-download');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('downloads the latest APK into the temporary directory', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode('apk-bytes'),
          200,
          headers: {'content-length': '9'},
        );
      });

      final service = AppUpdateService(
        httpClient: client,
        currentVersionProvider: () async => '1.1.0',
        temporaryDirectoryProvider: () async => tempDir,
        supportsOtaUpdates: true,
      );
      final updateInfo = AppUpdateInfo(
        currentVersion: SemanticVersion.parse('1.1.0'),
        latestVersion: SemanticVersion.parse('1.1.1'),
        releaseTag: 'v1.1.1',
        releasePageUrl: Uri.parse(
          'https://github.com/yukirawa/Deadline_management/releases/tag/v1.1.1',
        ),
        apkUrl: Uri.parse(
          'https://github.com/yukirawa/Deadline_management/releases/latest/download/app-release.apk',
        ),
      );
      final progressValues = <double>[];

      final file = await service.downloadLatestApk(
        updateInfo,
        progressValues.add,
      );

      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'apk-bytes');
      expect(progressValues.first, 0);
      expect(progressValues.last, 1);
    });
  });
}
