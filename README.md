# 締切レーダー（MVP）

Flutterで作成した期限管理アプリのMVPです。  
要件は [Docs/docs.md](./Docs/docs.md) を基準にしています。

## ディレクトリ構成

```text
.
├─ Docs/
│  └─ docs.md
├─ android/
├─ lib/
│  ├─ models/
│  │  ├─ task.dart
│  │  └─ task_type.dart
│  ├─ screens/
│  │  ├─ add_task_page.dart
│  │  └─ task_list_page.dart
│  ├─ services/
│  │  ├─ task_service.dart
│  │  └─ task_storage_service.dart
│  ├─ utils/
│  │  └─ deadline_utils.dart
│  ├─ widgets/
│  │  └─ task_card.dart
│  └─ main.dart
├─ test/
│  ├─ models/
│  ├─ services/
│  ├─ utils/
│  └─ widget_test.dart
└─ pubspec.yaml
```

## 起動方法

1. 依存パッケージ取得

```bash
flutter pub get
```

2. 接続デバイス確認

```bash
flutter devices
```

3. アプリ起動（Android想定）

```bash
flutter run
```

## テスト実行

```bash
flutter test
```
