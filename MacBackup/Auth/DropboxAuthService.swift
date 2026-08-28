import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// Dropbox の OAuth2 認証（PKCE 付き認可コードフロー）を担当する。
///
/// App secret を使わないため、デスクトップアプリでも secret を同梱せずに済む。
/// 取得したトークンは Keychain にのみ保存する。
@MainActor
final class DropboxAuthService: NSObject, ObservableObject {

    enum State: Equatable {
        case notConfigured          // App key 未設定
        case signedOut
        case authenticating
        case signedIn(accountID: String?)
        case needsReauthentication(reason: String)

        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .signedOut

    private let store: DropboxCredentialStore
    private let session: URLSession
    private var credentials: DropboxCredentials?
    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationProvider: WebAuthPresentationProvider?

    init(store: DropboxCredentialStore = DropboxCredentialStore(),
         session: URLSession = .shared) {
        self.store = store
        self.session = session
        super.init()
        restore()
    }

    var appKey: String? { AppConfig.dropboxAppKey }

    /// 起動時に Keychain から資格情報を読み戻す。
    func restore() {
        guard appKey != nil else {
            state = .notConfigured
            return
        }
        do {
            credentials = try store.load()
        } catch {
            credentials = nil
        }
        if let credentials {
            if credentials.isExpired() && credentials.refreshToken == nil {
                state = .needsReauthentication(reason: "アクセストークンの有効期限が切れました。")
            } else {
                state = .signedIn(accountID: credentials.accountID)
            }
        } else {
            state = .signedOut
        }
    }

    /// ブラウザ（ASWebAuthenticationSession）で Dropbox のログイン画面を開き、
    /// 認可コードを受け取ってトークンに交換する。
    func signIn() async throws {
        guard let appKey else {
            state = .notConfigured
            throw DropboxError.missingAppKey
        }
        state = .authenticating

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.makeCodeChallenge(from: verifier)
        let redirectURI = AppConfig.redirectURI(appKey: appKey)

        var components = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // リフレッシュトークンを得るために offline を指定する。
            URLQueryItem(name: "token_access_type", value: "offline")
        ]

        do {
            let callbackURL = try await presentWebAuth(
                url: components.url!,
                scheme: AppConfig.redirectScheme(appKey: appKey)
            )
            let code = try Self.authorizationCode(from: callbackURL)
            let credentials = try await exchange(code: code, verifier: verifier,
                                                 appKey: appKey, redirectURI: redirectURI)
            try store.save(credentials)
            self.credentials = credentials
            state = .signedIn(accountID: credentials.accountID)
        } catch {
            state = credentials == nil ? .signedOut : .needsReauthentication(reason: error.localizedDescription)
            throw error
        }
    }

    /// 保存済み資格情報を破棄する。
    func signOut() {
        try? store.clear()
        credentials = nil
        state = appKey == nil ? .notConfigured : .signedOut
    }

    /// 有効なアクセストークンを返す。期限が近ければリフレッシュを試みる。
    /// リフレッシュできない場合は再認証が必要であることを通知する。
    func validAccessToken() async throws -> String {
        guard appKey != nil else {
            state = .notConfigured
            throw DropboxError.missingAppKey
        }
        guard let current = credentials else {
            state = .signedOut
            throw DropboxError.authenticationRequired(nil)
        }
        guard current.isExpired() else { return current.accessToken }

        guard let refreshToken = current.refreshToken else {
            let reason = "アクセストークンの有効期限が切れました。"
            state = .needsReauthentication(reason: reason)
            throw DropboxError.authenticationRequired(reason)
        }
        do {
            let refreshed = try await refresh(using: refreshToken, existing: current)
            try store.save(refreshed)
            credentials = refreshed
            state = .signedIn(accountID: refreshed.accountID)
            return refreshed.accessToken
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .needsReauthentication(reason: reason)
            throw DropboxError.authenticationRequired(reason)
        }
    }

    /// 401 を受けた側から呼ぶ。UI を再認証待ちに落とす。
    func markReauthenticationRequired(reason: String) {
        state = .needsReauthentication(reason: reason)
    }

    // MARK: - OAuth の内部処理

    private func presentWebAuth(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: DropboxError.cancelled)
                    } else {
                        continuation.resume(throwing: DropboxError.network(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: DropboxError.unexpectedResponse("コールバック URL が空です。"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            let provider = WebAuthPresentationProvider(
                anchor: NSApplication.shared.keyWindow
                    ?? NSApplication.shared.windows.first
                    ?? ASPresentationAnchor()
            )
            self.presentationProvider = provider
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            if !session.start() {
                continuation.resume(throwing: DropboxError.unexpectedResponse("ブラウザを開けませんでした。"))
            }
        }
    }

    private static func authorizationCode(from url: URL) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return code
        }
        let description = items.first(where: { $0.name == "error_description" })?.value
            ?? items.first(where: { $0.name == "error" })?.value
            ?? url.absoluteString
        throw DropboxError.authenticationRequired(description)
    }

    private func exchange(code: String, verifier: String,
                          appKey: String, redirectURI: String) async throws -> DropboxCredentials {
        try await requestToken(form: [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": appKey,
            "code_verifier": verifier,
            "redirect_uri": redirectURI
        ], existing: nil)
    }

    private func refresh(using refreshToken: String,
                         existing: DropboxCredentials) async throws -> DropboxCredentials {
        guard let appKey else { throw DropboxError.missingAppKey }
        return try await requestToken(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": appKey
        ], existing: existing)
    }

    private func requestToken(form: [String: String],
                              existing: DropboxCredentials?) async throws -> DropboxCredentials {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(form).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DropboxError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DropboxError.unexpectedResponse("HTTP レスポンスではありません。")
        }
        guard (200...299).contains(http.statusCode) else {
            throw DropboxError.fromResponse(status: http.statusCode, body: data)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw DropboxError.unexpectedResponse("access_token を取得できませんでした。")
        }
        let expiresIn = json["expires_in"] as? Double
        return DropboxCredentials(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? existing?.refreshToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            accountID: (json["account_id"] as? String) ?? existing?.accountID
        )
    }

    private static func formEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    // MARK: - PKCE

    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func makeCodeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// ASWebAuthenticationSession にログイン画面の表示先ウィンドウを渡すための小さな委譲先。
/// メインアクター隔離された `DropboxAuthService` 自身に持たせると
/// nonisolated なコールバックから AppKit を触ることになるため、別クラスに切り出している。
final class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
