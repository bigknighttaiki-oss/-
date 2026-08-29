import Foundation

/// アップロード結果として Dropbox から返るファイルのメタデータ。
struct DropboxFileMetadata: Equatable, Sendable {
    /// Dropbox 上での最終的なファイル名。autorename により
    /// `filename (1).ext` のように変わっている場合がある。
    let name: String
    /// Dropbox 上のフルパス。
    let pathDisplay: String
    let size: Int64

    init(name: String, pathDisplay: String, size: Int64) {
        self.name = name
        self.pathDisplay = pathDisplay
        self.size = size
    }

    init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        self.name = name
        self.pathDisplay = (json["path_display"] as? String)
            ?? (json["path_lower"] as? String)
            ?? name
        self.size = (json["size"] as? Int64)
            ?? Int64((json["size"] as? Int) ?? 0)
    }
}

/// Dropbox API v2 を `URLSession` + REST で直接叩く軽量クライアント。
/// 外部 SDK には依存しない。
final class DropboxAPIClient: @unchecked Sendable {

    /// 1 リクエストで送りきる上限。これを超えるファイルは upload_session で分割送信する。
    /// Dropbox の上限は 150 MB。余裕を持って 140 MB を境界にする。
    static let singleShotLimit: Int64 = 140 * 1024 * 1024
    /// 分割送信時のチャンクサイズ。
    static let chunkSize: Int = 8 * 1024 * 1024

    private let session: URLSession
    private let tokenProvider: @Sendable () async throws -> String

    init(session: URLSession = URLSession(configuration: .default),
         tokenProvider: @escaping @Sendable () async throws -> String) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - アカウント情報

    /// 認証状態の確認に使う。
    func currentAccountEmail() async throws -> String? {
        var request = try await makeRequest(
            url: URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!
        )
        request.httpMethod = "POST"
        // このエンドポイントは body なし（Content-Type も付けない）。
        let (data, response) = try await performData(request)
        try validate(response: response, data: data)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["email"] as? String
    }

    // MARK: - アップロード

    /// ローカルファイルを Dropbox にアップロードする。
    ///
    /// - Parameters:
    ///   - fileURL: アップロード対象。
    ///   - remoteFolder: アップロード先フォルダ（例: `/MacBackup`）。
    ///   - progress: 0.0〜1.0 の進捗。
    /// - Returns: Dropbox が確定させたメタデータ。同名ファイルがあった場合は
    ///   `autorename: true` により Dropbox 側で連番が付き、その名前が返る。
    func upload(fileURL: URL,
                remoteFolder: String = AppConfig.defaultRemoteFolder,
                progress: @escaping @Sendable (Double) -> Void) async throws -> DropboxFileMetadata {

        let size = try fileSize(of: fileURL)
        let destination = Self.remotePath(folder: remoteFolder, fileName: fileURL.lastPathComponent)

        if size <= Self.singleShotLimit {
            return try await singleShotUpload(fileURL: fileURL, destination: destination,
                                              size: size, progress: progress)
        }
        return try await chunkedUpload(fileURL: fileURL, destination: destination,
                                       size: size, progress: progress)
    }

    private func singleShotUpload(fileURL: URL,
                                  destination: String,
                                  size: Int64,
                                  progress: @escaping @Sendable (Double) -> Void) async throws -> DropboxFileMetadata {
        var request = try await makeRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiArg([
            "path": destination,
            "mode": "add",
            // 同名ファイルがある場合は Dropbox 側で連番を付けて両方残す。
            // 自前でリネームロジックは持たない。
            "autorename": true,
            "mute": false,
            "strict_conflict": false
        ]), forHTTPHeaderField: "Dropbox-API-Arg")

        let delegate = UploadProgressDelegate { sent, total in
            let expected = total > 0 ? total : size
            guard expected > 0 else { return }
            progress(min(1.0, Double(sent) / Double(expected)))
        }

        let (data, response) = try await performUpload(request, fromFile: fileURL, delegate: delegate)
        try validate(response: response, data: data)
        progress(1.0)
        return try Self.metadata(from: data)
    }

    /// 150 MB を超えるファイルは upload_session で分割送信する。
    /// 空のセッションを開いてから、チャンクごとに append し、最後のチャンクで finish する。
    private func chunkedUpload(fileURL: URL,
                               destination: String,
                               size: Int64,
                               progress: @escaping @Sendable (Double) -> Void) async throws -> DropboxFileMetadata {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw DropboxError.localFileUnavailable(fileURL.path)
        }
        defer { try? handle.close() }

        let sessionID = try await startUploadSession()
        var offset: Int64 = 0

        while offset < size {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
            } catch {
                throw DropboxError.localFileUnavailable(fileURL.path)
            }
            // 途中でファイルが切り詰められた場合もここに来る。
            if chunk.isEmpty {
                throw DropboxError.localFileUnavailable(fileURL.path)
            }

            let sentBefore = offset
            let onProgress: @Sendable (Int64, Int64) -> Void = { sent, _ in
                progress(min(1.0, max(0.0, Double(sentBefore + sent) / Double(size))))
            }

            let isLast = (offset + Int64(chunk.count)) >= size
            if isLast {
                let metadata = try await finishUploadSession(sessionID: sessionID,
                                                             offset: offset,
                                                             chunk: chunk,
                                                             destination: destination,
                                                             onProgress: onProgress)
                progress(1.0)
                return metadata
            }
            try await appendToUploadSession(sessionID: sessionID, offset: offset,
                                            chunk: chunk, onProgress: onProgress)
            offset += Int64(chunk.count)
        }
        throw DropboxError.unexpectedResponse("アップロードセッションが完了しませんでした。")
    }

    private func startUploadSession() async throws -> String {
        var request = try await makeRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload_session/start")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiArg(["close": false]), forHTTPHeaderField: "Dropbox-API-Arg")

        let (data, response) = try await performUpload(request, from: Data(),
                                                       delegate: UploadProgressDelegate { _, _ in })
        try validate(response: response, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = json["session_id"] as? String else {
            throw DropboxError.unexpectedResponse("session_id を取得できませんでした。")
        }
        return sessionID
    }

    private func appendToUploadSession(sessionID: String,
                                       offset: Int64,
                                       chunk: Data,
                                       onProgress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        var request = try await makeRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload_session/append_v2")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiArg([
            "cursor": ["session_id": sessionID, "offset": offset],
            "close": false
        ]), forHTTPHeaderField: "Dropbox-API-Arg")

        let (data, response) = try await performUpload(request, from: chunk,
                                                       delegate: UploadProgressDelegate(onProgress: onProgress))
        try validate(response: response, data: data)
    }

    private func finishUploadSession(sessionID: String,
                                     offset: Int64,
                                     chunk: Data,
                                     destination: String,
                                     onProgress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> DropboxFileMetadata {
        var request = try await makeRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload_session/finish")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiArg([
            "cursor": ["session_id": sessionID, "offset": offset],
            "commit": [
                "path": destination,
                "mode": "add",
                "autorename": true,
                "mute": false,
                "strict_conflict": false
            ]
        ]), forHTTPHeaderField: "Dropbox-API-Arg")

        let (data, response) = try await performUpload(request, from: chunk,
                                                       delegate: UploadProgressDelegate(onProgress: onProgress))
        try validate(response: response, data: data)
        return try Self.metadata(from: data)
    }

    // MARK: - 共通処理

    private func makeRequest(url: URL) async throws -> URLRequest {
        let token = try await tokenProvider()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }
    }

    private func performUpload(_ request: URLRequest,
                               fromFile fileURL: URL,
                               delegate: UploadProgressDelegate) async throws -> (Data, URLResponse) {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw DropboxError.localFileUnavailable(fileURL.path)
        }
        do {
            return try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
        } catch {
            throw Self.mapTransportError(error, fileURL: fileURL)
        }
    }

    private func performUpload(_ request: URLRequest,
                               from data: Data,
                               delegate: UploadProgressDelegate) async throws -> (Data, URLResponse) {
        do {
            return try await session.upload(for: request, from: data, delegate: delegate)
        } catch {
            throw Self.mapTransportError(error)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DropboxError.unexpectedResponse("HTTP レスポンスではありません。")
        }
        guard (200...299).contains(http.statusCode) else {
            // 容量不足なども含め、Dropbox のメッセージをそのまま伝える。
            throw DropboxError.fromResponse(status: http.statusCode, body: data)
        }
    }

    private func fileSize(of url: URL) throws -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                throw DropboxError.localFileUnavailable(url.path)
            }
            return Int64(values.fileSize ?? 0)
        } catch let error as DropboxError {
            throw error
        } catch {
            throw DropboxError.localFileUnavailable(url.path)
        }
    }

    private static func mapTransportError(_ error: Error, fileURL: URL? = nil) -> DropboxError {
        if let dropboxError = error as? DropboxError { return dropboxError }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError].contains(nsError.code) {
            return .localFileUnavailable(fileURL?.path ?? nsError.localizedDescription)
        }
        return .network(error.localizedDescription)
    }

    private static func metadata(from data: Data) throws -> DropboxFileMetadata {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = DropboxFileMetadata(json: json) else {
            throw DropboxError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "(本文なし)")
        }
        return metadata
    }

    /// アップロード先のフルパスを組み立てる。
    static func remotePath(folder: String, fileName: String) -> String {
        var normalized = folder.trimmingCharacters(in: .whitespaces)
        if !normalized.hasPrefix("/") { normalized = "/" + normalized }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        return "\(normalized)/\(fileName)"
    }

    /// `Dropbox-API-Arg` ヘッダー用の JSON 文字列。
    ///
    /// HTTP ヘッダーは ASCII しか安全に運べないため、非 ASCII 文字（日本語のファイル名など）は
    /// `\uXXXX` にエスケープする。Dropbox はこの形式を受け付ける。
    static func apiArg(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return asciiEscaped(json)
    }

    static func asciiEscaped(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            if scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else {
                for unit in String(scalar).utf16 {
                    result += String(format: "\\u%04x", unit)
                }
            }
        }
        return result
    }
}
