# PROJECT_STATE.md - AltFiler 開発ステータス・変更履歴

## 現在のバージョン
- **Version**: `v1.0.3`
- **Build**: `1`
- **最終更新**: 2026-10-28 (JST)

---

## 完了済みフェーズ

### ✅ フェーズ1：個人用機能の完全廃止とリブランディング (`v1.0.0`)
1. **機密情報・個人識別子の完全排除監査＆クリーンアップ**:
   - 旧ベースコード（Entropy Filer）に含まれていた Gemini API キー（`AQ.` 始まり）、Google OAuth Client ID / Client Secret / API キー、個人バンドル識別子を1文字たりとも残さず完全撤去。
   - `GoogleDriveManager.swift`, `GoogleDriveView.swift`, `ProvisioningInfo.swift` を完全廃止。
2. **音声プレイヤーUIの一本化**:
   - `GeminiLyricsService` および上部セグメントタブを廃止し、洗練された「ファイル情報カード（`CosmicAudioFileInfoView`）」のみのプレイヤーUIに統一。
3. **キャッシュ自動パージ化＆外付けストレージメニュー撤去**:
   - 手動パージボタンおよび外付けドライブ関連コードを削除し、アプリ起動時（`onAppear`）およびバックグラウンド移行時に `/tmp` をサイレント自動パージする設計へ統一。
4. **フォルダロック認証の厳格化**:
   - 無条件の「全フォルダロックのリセット」ボタンおよび `resetAllLocks()` を廃止。
   - フォルダのロック設定・解除・保護オフすべてにおいて、生体認証（Face ID / Touch ID）または現在のマスターパスワード認証を必須化。
5. **ShareExtension の汎用化**:
   - `ShareExtension/ShareViewController.swift` 内の App Group ID 解決ロジックから個人IDを排除し、メインバンドルIDから動的に `group.<MainBundleID>` を解決する安全設計に改修。

### ✅ フェーズ2：リリース版向け新規実装・機能強化 (`v1.0.1` 〜 `v1.0.3`)
1. **機能群①：セキュリティ・認証基盤の製品レベル強化 (`v1.0.1`)**:
   - `FolderLockManager.swift` を `CryptoKit`（SHA-256）＋ iOS `Keychain`（`Security` フレームワーク、`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）によるセキュア保存へ完全移行。
   - アプリ起動時・バックグラウンド復帰時に認証を要求する「アプリ起動時ロック（`AppLockOverlayView`）」を実装。
   - マルチタスク画面（App Switcher）移行時に即座に画面をブラー保護する「バックグラウンド覗き見防止シールド（`PrivacyShieldOverlayView`）」を実装。
   - 現在のパスワードまたは生体認証で本人確認した上で変更する「マスターパスワード設定・変更シート（`MasterPasswordChangeSheet`）」を実装。
2. **機能群②：ファイル管理・UXの製品版ブラッシュアップ (`v1.0.2`)**:
   - iOS標準の `Foundation` + `Compression`（`COMPRESSION_ZLIB`）のみで動作する純粋Swift製ZIPエンジン（`ZipArchiver.swift`）を新規実装。コンテキストメニューおよび複数選択バーからの `.zip` 圧縮と、`.zip` ファイルタップ（またはコンテキストメニュー）での即座解凍（Zip-Slip防御・UTF-8/Shift-JIS対応）をサポート。
   - 初回起動時に3枚のカードで魅力と使い方を案内する「オンボーディング画面（`OnboardingSheetView`）」を実装。
   - ヘッダーおよび3点リーダメニューから開ける「設定・アプリ情報画面（`SettingsSheetView`）」およびアプリ内「プライバシーポリシー」「利用規約」シートを新設。
   - App Store Connect 審査提出用のサポートURL・プライバシーポリシーURLとしてそのまま公開できる GitHub Pages ファイル（`docs/index.html`）を作成。
3. **機能群③：新規アプリアイコンの作成 (`v1.0.3`)**:
   - 「独立ファイル管理（グラスモーフィズムのフォルダ）」×「高機能メディアプレイヤー（ネオンシアンの再生トライアングル＆サウンドウェーブ）」を融合した 1024×1024px（24bit RGB・アルファなし）の新規アプリアイコンを作成し、`AltFiler/Assets.xcassets/AppIcon.appiconset/AppIcon.png` に配置。
