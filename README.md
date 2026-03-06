# 締切レーダー v1.0

Flutter製の締切管理アプリです。  
v1.0 では **Web + Android 同期**、**Googleログイン必須**、**リアルタイム同期**、**通知要約配信**に対応しています。

## v1.0 で追加した機能

- Googleログイン（Web: Popup優先+Redirectフォールバック）
- Cloud Firestore によるリアルタイム同期
- Web対応（`/deadline/` 配下で配信想定）
- v0.2機能: 編集 / 削除（論理削除）/ 検索 / フィルタ
- ごみ箱画面（復元 + 完全削除）
- 論理削除30日超の自動パージ（起動時）
- FCM による要約通知（前日19:00 / 当日07:00）

## Firestore データ構造

- `users/{uid}/tasks/{taskId}`
- `users/{uid}/settings/profile`
- `users/{uid}/devices/{deviceId}`
- `users/{uid}/notification_slots/{slotKey}`

## セットアップ

1. 依存取得

```bash
flutter pub get
```

2. Firebaseプロジェクト作成
- Authentication: Google を有効化
- Firestore を有効化
- Cloud Messaging を有効化
- Cloud Functions を有効化

3. Firebase Auth 許可ドメインへ本番HTTPSドメインを追加

4. Flutter実行時に Firebase 設定値を `--dart-define` で渡す

```bash
flutter run -d chrome ^
  --dart-define=FIREBASE_PROJECT_ID=xxx ^
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=xxx ^
  --dart-define=FIREBASE_AUTH_DOMAIN=xxx.firebaseapp.com ^
  --dart-define=FIREBASE_STORAGE_BUCKET=xxx.firebasestorage.app ^
  --dart-define=FIREBASE_WEB_API_KEY=xxx ^
  --dart-define=FIREBASE_WEB_APP_ID=xxx ^
  --dart-define=FIREBASE_WEB_MEASUREMENT_ID=xxx ^
  --dart-define=FIREBASE_ANDROID_API_KEY=xxx ^
  --dart-define=FIREBASE_ANDROID_APP_ID=xxx ^
  --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com ^
  --dart-define=WEB_PUSH_CERT_KEY=xxx
```

5. Android向け `android/app/google-services.json` を配置

6. Web通知用 `web/firebase-messaging-sw.js` のプレースホルダ値を本番値へ置換

## 実行

- Web

```bash
flutter run -d chrome
```

- Android

```bash
flutter run -d android
```

## テスト

```bash
flutter analyze
flutter test
```

## Webビルド（/deadline 配下）

```bash
flutter build web --release --base-href /deadline/
```

## Nginx 配備例（Path URL対応）

```nginx
location /deadline/ {
  alias /var/www/deadline/;
  try_files $uri $uri/ /deadline/index.html;
}
```

ビルド成果物 `build/web` を `/var/www/deadline/` に配置します。

## Functions 配備

```bash
cd functions
npm install
cd ..
firebase deploy --only firestore:rules,firestore:indexes,functions
```

`functions/index.js` の `sendDeadlineSummary` が 15分ごとに実行され、  
ユーザーTZ基準で 07:00 / 19:00 の slot で要約通知を送信します。
