import Foundation

/// Dropbox API とのやり取りで発生しうるエラー。
///
/// 方針: API が返したメッセージは加工せずそのまま見せる。
/// 容量不足などを憶測で言い換えない（「〜かもしれません」といった曖昧な表示をしない）。
enum DropboxError: LocalizedError, Equatable {

    /// App key が未設定。
    case missingAppKey
    /// 未認証、またはトークンが失効して再認証が必要。
    case authenticationRequired(String?)
    /// Dropbox がエラーを返した。`summary` は API の error_summary をそのまま保持する。
    case api(status: Int, summary: String, userMessage: String?)
    /// 通信エラー（オフライン、タイムアウトなど）。リトライ可能。
    case network(String)
    /// アップロード対象のファイルが読めない（削除・移動された等）。スキップ対象。
    case localFileUnavailable(String)
    /// 想定外のレスポンス。
    case unexpectedResponse(String)
    /// ユーザーが認証をキャンセルした。
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAppKey:
            return "Dropbox の App key が設定されていません。設定画面の手順に従って App key を登録してください。"
        case .authenticationRequired(let detail):
            if let detail, !detail.isEmpty {
                return "Dropbox の認証が必要です: \(detail)"
            }
            return "Dropbox の認証が必要です。"
        case .api(let status, let summary, let userMessage):
            // API のメッセージを尊重してそのまま提示する。
            if let userMessage, !userMessage.isEmpty {
                return "Dropbox エラー (HTTP \(status)): \(userMessage)"
            }
            return "Dropbox エラー (HTTP \(status)): \(summary)"
        case .network(let message):
            return "ネットワークエラー: \(message)"
        case .localFileUnavailable(let path):
            return "ファイルが見つからないか読み取れません: \(path)"
        case .unexpectedResponse(let detail):
            return "想定外のレスポンスを受け取りました: \(detail)"
        case .cancelled:
            return "処理はキャンセルされました。"
        }
    }

    /// 再認証を促すべきエラーかどうか。
    var requiresReauthentication: Bool {
        switch self {
        case .authenticationRequired:
            return true
        case .api(let status, _, _):
            return status == 401
        default:
            return false
        }
    }

    /// 「リトライ」ボタンを出すべきエラーかどうか（自動リトライはしない）。
    var isRetryable: Bool {
        switch self {
        case .network:
            return true
        case .api(let status, _, _):
            return status == 429 || (500...599).contains(status)
        default:
            return false
        }
    }

    /// アップロード対象からスキップすべきエラーかどうか。
    var isSkippable: Bool {
        if case .localFileUnavailable = self { return true }
        return false
    }

    /// Dropbox のエラーレスポンス JSON を解釈する。
    /// 解釈できない場合も本文をそのまま保持する。
    static func fromResponse(status: Int, body: Data) -> DropboxError {
        let raw = String(data: body, encoding: .utf8) ?? "(本文なし)"
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            if status == 401 { return .authenticationRequired(raw) }
            return .api(status: status, summary: raw, userMessage: nil)
        }
        let summary = (json["error_summary"] as? String)
            ?? (json["error_description"] as? String)
            ?? (json["error"] as? String)
            ?? raw
        let userMessage = (json["user_message"] as? [String: Any])?["text"] as? String
        if status == 401 {
            return .authenticationRequired(userMessage ?? summary)
        }
        return .api(status: status, summary: summary, userMessage: userMessage)
    }
}
