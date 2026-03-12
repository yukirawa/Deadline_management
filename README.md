# 締切レーダー

Web アプリ:
https://yukirawa.jp/deadline/

Android 配布ページ:
https://github.com/yukirawa/Deadline_management/releases

Google アカウントでログインして利用します。

## Android OTA アップデート

- `v1.1.0` 以降の Android 版は cold start ごとに GitHub Releases の latest release を確認します。
- 最新リリースの tag は `v<versionName>` 形式、APK asset 名は `app-release.apk` 固定です。
- 新しい signed APK が見つかった場合だけ、ユーザー確認後にダウンロードして Android のインストーラへ渡します。
- 既存の `v1.0.0` 配布版には updater が入っていないため、最初の updater 同梱版である `v1.1.0` だけは手動で入れ替えてください。

## バージョン運用

- バージョン形式は `vX.Y.Z` を使います。
- `X` はメジャーバージョンです。大型刷新や互換性に影響する変更で上げます。
- `Y` はマイナーバージョンです。新機能追加や機能改善で上げます。
- `Z` はパッチバージョンです。バグ修正で上げます。
- OTA 更新判定はこの `X.Y.Z` をそのまま比較するため、今後 `v1.1.1`、`v1.2.0`、`v2.0.0` のように増えていっても追加実装は不要です。

## Android リリース手順

- 詳細は [Docs/android_ota_release.md](Docs/android_ota_release.md) を参照してください。
- production APK は毎回同じ release keystore で署名してください。debug signing の APK を配布すると OTA 更新できません。
- GitHub Release の tag だけを `v1.2.0` に変えても、APK 内の versionName は変わりません。必ず先に `pubspec.yaml` を更新してからビルドしてください。
