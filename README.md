# Mac Backup & Storage Manager

macOS ネイティブアプリ（SwiftUI）。写真や音楽制作のデモファイルを Dropbox に
退避し、ローカルの不要ファイルを安全に片付けるためのツール。個人利用向け。

現在の実装範囲は **フェーズ1: Dropbox 連携バックアップ機能** です。

---

## フェーズ1でできること

- Dropbox の OAuth2 認証（PKCE 付き認可コードフロー、App secret 不要）
  - トークンは **Keychain** にのみ保存。UserDefaults への平文保存はしない
  - 期限切れ時はリフレッシュトークンで自動更新し、失敗したら再認証を促す
- `NSOpenPanel` で選んだファイル（複数可）を `/MacBackup/` にアップロード
- ファイルごと／全体のプログレスバー
- 同名ファイルは Dropbox API の `autorename: true` で連番付きにして両方残す
  （自前のリネームロジックは持たない。結果一覧にリネーム後の名前を表示する）
- アップロード成功後の削除確認
  - 既定は「残す」。チェックは全て外れた状態で開く
  - 「すべて削除」「すべて残す」＋ファイルごとの個別選択
  - 削除は `FileManager.trashItem(at:resultingItemURL:)` で **ゴミ箱へ移動**。
    完全削除はしない
- エラーハンドリング
  - ネットワークエラー: 自動リトライはせず、リトライボタンを出す
  - 認証エラー: 再認証ダイアログ
  - Dropbox のエラー（容量不足を含む）: API の `error_summary` / `user_message`
    をそのまま表示し、こちらで言い換えない
  - アップロード中にファイルが消えた／移動された: スキップして次へ進み、
    最後に「スキップされたファイル」として報告

フェーズ1の範囲外（ストレージスキャン・可視化、自動バックアップ、
Dropbox 退避を伴わない削除、重複ファイル検出）は未実装です。

---

## 事前準備（人間が手で行う作業）

1. [Dropbox Developer Console](https://www.dropbox.com/developers/apps) で
   アプリを作成する
   - API: **Scoped access**
   - アクセス範囲: App folder / Full Dropbox のどちらでも可
   - Permissions タブで `files.content.write`、`files.content.read`、
     `account_info.read` にチェックして Submit
   - Settings タブの **Redirect URIs** に次を追加
     （`<APP_KEY>` は同じ画面の App key に置き換える）:

     ```
     db-<APP_KEY>://2/token
     ```

2. App key をアプリに渡す。**App secret は不要**（PKCE を使うため）。
   次のいずれかを設定すれば動く（上から順に探索される）:

   1. 環境変数 `DROPBOX_APP_KEY`
      （Xcode の Product > Scheme > Edit Scheme… > Run > Arguments >
      Environment Variables で設定するのが手軽）
   2. `~/Library/Application Support/MacBackup/DropboxConfig.plist` の `AppKey`

      ```sh
      mkdir -p ~/Library/Application\ Support/MacBackup
      cp MacBackup/Config/DropboxConfig.example.plist \
         ~/Library/Application\ Support/MacBackup/DropboxConfig.plist
      # AppKey の値を自分の App key に書き換える
      ```
   3. アプリバンドルに `DropboxConfig.plist` を同梱する
      （Xcode のターゲットに追加する。App key がリポジトリに入らないよう注意）

   App key が見つからない場合、アプリは設定画面でこの手順を案内します。

3. Xcode で `MacBackup.xcodeproj` を開き、署名チームを自分の Apple ID に設定して
   ビルド・実行する（自分用のローカルビルドなので公証は不要）。

---

## ビルド

```sh
open MacBackup.xcodeproj
```

- ターゲット: macOS 13 (Ventura) 以降 / Swift 5.9
- 外部依存なし。Dropbox API v2 は `URLSession` + REST で直接呼んでいる
  （SwiftyDropbox は使っていない）
- App Sandbox は有効。エンタイトルメントは
  ネットワーククライアント + ユーザー選択ファイルの読み書きのみ

ファイルを追加・削除したら、Xcode プロジェクトを作り直せる:

```sh
python3 Scripts/generate_xcodeproj.py   # 同梱のジェネレーター
# または
xcodegen generate                        # project.yml から生成（XcodeGen 使用時）
```

---

## ディレクトリ構成

```
MacBackup/
  MacBackupApp.swift          アプリのエントリポイント
  Config/                     App key の読み込み（環境変数 / plist）
  Security/                   Keychain ラッパー
  Auth/                       OAuth2 (PKCE) と資格情報の保存
  Networking/                 Dropbox API v2 クライアント、エラー定義
  Backup/                     アップロード進行管理、ゴミ箱への移動
  Classification/             ファイル種別の分類（フェーズ2 の可視化で再利用）
  Views/                      SwiftUI 画面
  Resources/                  Info.plist / entitlements
Scripts/generate_xcodeproj.py Xcode プロジェクト生成
```

`Classification/FileCategory.swift` は UI やアップロード処理から独立させてあり、
フェーズ2 のストレージスキャン・グラフ表示でそのまま使える。
削除処理（`Backup/LocalFileRemover.swift`）と削除確認 UI も、
フェーズ3 の「クラウド退避して削除／そのまま削除／スキップ」の 3 択に
拡張しやすいよう分離してある。

---

## 動作確認について

Xcode でのビルドとシミュレーター／実機での動作確認は人間が行う想定です。
このリポジトリにはコード生成までが含まれます。
