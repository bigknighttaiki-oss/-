import Foundation

/// アプリ全体の設定値。
///
/// Dropbox の App key は Claude Code / リポジトリには含めない。
/// 人間が Dropbox Developer Console でアプリ登録して取得した App key を、
/// 次のいずれかの方法で与える（上から順に探索する）:
///
/// 1. 環境変数 `DROPBOX_APP_KEY`
///    （Xcode の Scheme > Run > Arguments > Environment Variables で設定）
/// 2. `~/Library/Application Support/MacBackup/DropboxConfig.plist` の `AppKey`
/// 3. アプリバンドルに同梱した `DropboxConfig.plist` の `AppKey`
///
/// App secret は使わない。デスクトップアプリでは secret を安全に保持できないため、
/// PKCE (Proof Key for Code Exchange) 付きの OAuth2 認可コードフローを使う。
enum AppConfig {

    /// Dropbox 上のアップロード先フォルダ。
    /// フェーズ1では固定。将来は設定画面から変更できるようにする。
    static let defaultRemoteFolder = "/MacBackup"

    /// 設定ファイル名。
    static let configFileName = "DropboxConfig.plist"

    /// ユーザーごとの設定ファイル置き場。
    static var userConfigURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("MacBackup", isDirectory: true)
            .appendingPathComponent(configFileName)
    }

    /// Dropbox App key。未設定なら nil を返し、UI 側で設定手順を案内する。
    static var dropboxAppKey: String? {
        if let fromEnv = ProcessInfo.processInfo.environment["DROPBOX_APP_KEY"],
           !fromEnv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fromEnv.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let fromUserConfig = appKey(inPlistAt: userConfigURL) {
            return fromUserConfig
        }
        if let bundled = Bundle.main.url(forResource: "DropboxConfig", withExtension: "plist"),
           let fromBundle = appKey(inPlistAt: bundled) {
            return fromBundle
        }
        return nil
    }

    /// OAuth のリダイレクト先スキーム。Dropbox の慣例に合わせて `db-<appkey>` を使う。
    /// Developer Console の Redirect URIs にも `db-<appkey>://2/token` を登録しておくこと。
    static func redirectScheme(appKey: String) -> String {
        "db-\(appKey)"
    }

    static func redirectURI(appKey: String) -> String {
        "\(redirectScheme(appKey: appKey))://2/token"
    }

    private static func appKey(inPlistAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let key = dict["AppKey"] as? String
        else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "YOUR_DROPBOX_APP_KEY" ? nil : trimmed
    }
}
