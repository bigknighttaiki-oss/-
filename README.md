# Mac Backup & Storage Manager

macOS ネイティブアプリ（SwiftUI）。写真や音楽制作のデモファイルを Dropbox に
退避し、ローカルの不要ファイルを安全に片付けるためのツール。個人利用向け。

実装済みの範囲は **フェーズ1: Dropbox 連携バックアップ** と
**フェーズ2: ストレージスキャン・可視化** です。

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

## フェーズ2でできること

- 選んだフォルダ以下を走査し、種別（写真 / 動画 / 音楽 / 書類 / アーカイブ /
  キャッシュ / アプリ / その他）ごとに使用容量を集計
  - 走査はメインスレッドの外で動き、途中で中断できる
  - `.app` や `.logicx` などのパッケージは 1 個のファイルとして扱い、
    中身の合計サイズを持たせる
  - シンボリックリンクは実体を二重に数えないよう除外
  - ディスク上の占有サイズ（`totalFileAllocatedSize`）で集計する
- Swift Charts による可視化
  - 円グラフ（macOS 14 以降。macOS 13 では 100% 積み上げ棒にフォールバック）
  - 種別ごとの使用容量の横棒グラフ
  - ボリュームの空き容量バー
  - 同じ数字を読める内訳の表
- 容量の大きいファイル上位一覧（クリックで Finder に表示）
- 権限が無くて読めなかったパスの報告

配色は種別に固定で割り当ててあり、並び替えても色は動かない。
ライト／ダークそれぞれの背景に合わせて別々に選び、色覚特性のシミュレーション込みで
検証している（隣接ペアの最悪値: CVD ΔE 9.1 ライト / 8.4 ダーク）。
ライトモードでは一部の色が背景とのコントラスト 3:1 に届かないため、
グラフには必ず直接ラベルと内訳表を添えて、色だけに意味を持たせないようにしている。

未実装（フェーズ3）: 「クラウド退避して削除」「そのまま削除」「スキップ」の
3 択 UI、自動バックアップ、重複ファイル検出。

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
- 共有スキーム `MacBackup` を追跡しているので、`xcodebuild -scheme MacBackup`
  がそのまま使える
- App Sandbox は有効。エンタイトルメントは
  ネットワーククライアント + ユーザー選択ファイルの読み書きのみ

GitHub Actions（`.github/workflows/build.yml`）が、push と PR のたびに
macOS ランナーで `xcodebuild` を流してビルドが通るか確認する。
CI では署名しない（個人用のローカルビルドが前提のため）。

ファイルを追加・削除したら、Xcode プロジェクトを作り直せる:

```sh
python3 Scripts/generate_xcodeproj.py   # 同梱のジェネレーター（共有スキームも作る）
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
  Classification/             ファイル種別の分類（フェーズ1・2 で共用）
  Scanning/                   フォルダ走査と集計（フェーズ2）
  Views/                      SwiftUI 画面
  Resources/                  Info.plist / entitlements
Scripts/generate_xcodeproj.py Xcode プロジェクト生成
```

`Classification/FileCategory.swift` は UI やアップロード処理から独立していて、
フェーズ1 の結果一覧とフェーズ2 の集計の両方で使っている。
`Scanning/StorageScanner.swift` も UI に依存しない同期処理で、
`Task.detached` から呼ぶ前提。削除処理（`Backup/LocalFileRemover.swift`）と削除確認 UI も、
フェーズ3 の「クラウド退避して削除／そのまま削除／スキップ」の 3 択に
拡張しやすいよう分離してある。

---

## 動作確認について

Xcode でのビルドとシミュレーター／実機での動作確認は人間が行う想定です。
このリポジトリにはコード生成までが含まれます。
