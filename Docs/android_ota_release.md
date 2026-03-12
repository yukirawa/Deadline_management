# Android OTA Release Steps

## 前提

- `pubspec.yaml` の `version:` は `x.y.z+build` 形式にする
- GitHub Release の tag は必ず `v<versionName>` にする
- Android の配布 asset 名は必ず `app-release.apk` にする
- 毎回同じ production keystore で署名する
- `scripts/release.ps1` と Gradle は `android/key.properties` が無い、または不完全な状態では release build を失敗させる

## Versioning Policy

- `versionName` は semver の `X.Y.Z` で管理する
- `X`: 大型刷新、互換性影響、メジャーリリース
- `Y`: 新機能追加、機能改善
- `Z`: バグ修正
- 例:
  - `v1.0.0` 初回リリース
  - `v1.1.0` 新機能追加
  - `v1.1.1` バグ修正
  - `v1.2.0` 機能改善
  - `v2.0.0` 大型刷新
- OTA ロジックは `v<versionName>` を汎用比較するので、将来の版数増加に合わせたコード変更は不要

## 事前準備

1. `android/key.properties.example` を `android/key.properties` にコピーする
2. `storeFile`, `storePassword`, `keyAlias`, `keyPassword` を本番用 keystore に合わせて設定する
3. `config/dart_defines.prod.json` を用意する
4. `pubspec.yaml` の `versionName` を次の配布版へ更新する

## ビルド

1. `pwsh ./scripts/release.ps1 -SkipWebDeploy`
2. 生成物は `build/app/outputs/flutter-apk/app-release.apk`
3. スクリプトの出力に表示される expected tag が `v<versionName>` になっていることを確認する
4. GitHub で公開する tag が決まっている場合は `pwsh ./scripts/release.ps1 -SkipWebDeploy -ReleaseTag v<versionName>` を使って、`pubspec.yaml` と不一致がないことを確認する
5. signing 関連のエラーで build が止まった場合は公開しない。`android/key.properties` を修正し、インストール済みアプリと同じ release keystore を使って再ビルドする

## Release Signing Safety

- OTA updates only work when every published APK is signed with the same production keystore as the installed app.
- A debug-signed APK can download successfully but Android will reject it during update as an invalid package.

## GitHub Releases

1. GitHub で tag `v<versionName>` の release を作成する
2. `build/app/outputs/flutter-apk/app-release.apk` をそのまま asset としてアップロードする
3. asset 名が `app-release.apk` になっていることを確認する
4. release を publish する

## 運用メモ

- 既存の `v1.0.0` 配布版には updater が入っていないため、`v1.1.0` は手動配布が必要
- `versionName` を変えずに APK を差し替える運用はしない
- keystore が変わると既存ユーザーは上書き更新できない
- GitHub Release の tag を先に上げても APK の `versionName` は変わらない。必ず `pubspec.yaml` を更新してからビルドする
