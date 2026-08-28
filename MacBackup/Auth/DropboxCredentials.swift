import Foundation

/// Dropbox の OAuth2 トークン一式。Keychain には JSON にして保存する。
struct DropboxCredentials: Codable, Equatable {
    var accessToken: String
    /// `token_access_type=offline` で認証した場合に得られるリフレッシュトークン。
    var refreshToken: String?
    /// アクセストークンの失効時刻。
    var expiresAt: Date?
    var accountID: String?

    /// 期限が近い（もしくは切れている）かどうか。
    /// 通信中に切れるのを避けるため、5 分のマージンを取る。
    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= 300
    }
}

/// Keychain に置かれた資格情報の入出力。
struct DropboxCredentialStore {
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func load() throws -> DropboxCredentials? {
        guard let data = try keychain.load() else { return nil }
        return try JSONDecoder().decode(DropboxCredentials.self, from: data)
    }

    func save(_ credentials: DropboxCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(data)
    }

    func clear() throws {
        try keychain.delete()
    }
}
