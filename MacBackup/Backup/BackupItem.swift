import Foundation

/// アップロード 1 ファイル分の状態。
struct BackupItem: Identifiable, Equatable {

    enum Status: Equatable {
        case pending
        case uploading(progress: Double)
        /// 成功。`metadata.name` は Dropbox 側で autorename された後の名前。
        case succeeded(metadata: DropboxFileMetadata)
        /// 失敗。リトライ対象。
        case failed(message: String, retryable: Bool)
        /// アップロード中にファイルが削除・移動されていたなどの理由で飛ばした。
        case skipped(reason: String)

        var isFinished: Bool {
            switch self {
            case .succeeded, .failed, .skipped: return true
            case .pending, .uploading: return false
            }
        }

        var isSuccess: Bool {
            if case .succeeded = self { return true }
            return false
        }

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        var isSkipped: Bool {
            if case .skipped = self { return true }
            return false
        }

        var progress: Double {
            switch self {
            case .pending: return 0
            case .uploading(let progress): return progress
            case .succeeded: return 1
            case .failed, .skipped: return 0
            }
        }
    }

    let id: UUID
    let url: URL
    /// アップロード前に測ったローカルのファイルサイズ（バイト）。不明なら 0。
    let byteSize: Int64
    var status: Status
    /// アップロード完了後の削除確認で「削除する」が選ばれているか。
    /// 誤操作を防ぐため、初期値は false（＝残す）。
    var isMarkedForDeletion: Bool

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.byteSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
        self.status = .pending
        self.isMarkedForDeletion = false
    }

    /// デモ表示用。ディスク上に無いファイルでも、サイズを指定して組み立てられる。
    init(demoURL: URL, byteSize: Int64) {
        self.id = UUID()
        self.url = demoURL
        self.byteSize = byteSize
        self.status = .pending
        self.isMarkedForDeletion = false
    }

    var fileName: String { url.lastPathComponent }

    /// フェーズ2 のスキャン機能で使う分類。ここでは結果一覧のアイコン表示に使う。
    var category: FileCategory { FileCategory.classify(url: url) }

    /// Dropbox 側で名前が変わったか（autorename が働いたか）。
    var wasRenamedByDropbox: Bool {
        guard case .succeeded(let metadata) = status else { return false }
        return metadata.name != fileName
    }
}
