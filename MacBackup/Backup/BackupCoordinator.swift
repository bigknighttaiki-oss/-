import Foundation

/// バックアップ（アップロード → 結果表示 → ローカル削除確認）の進行を管理する。
@MainActor
final class BackupCoordinator: ObservableObject {

    enum Phase: Equatable {
        case idle
        case uploading
        /// 全ファイルの処理が終わり、結果一覧と削除確認を出す段階。
        case review
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [BackupItem] = []
    @Published private(set) var currentItemID: BackupItem.ID?
    /// 認証エラー時に立てるフラグ。UI 側で再認証ダイアログを出す。
    @Published var authenticationErrorMessage: String?
    /// ゴミ箱への移動結果。
    @Published private(set) var trashOutcomes: [LocalFileRemover.Outcome] = []
    @Published var remoteFolder: String = AppConfig.defaultRemoteFolder

    private let client: DropboxAPIClient
    private let auth: DropboxAuthService
    private let remover: LocalFileRemover
    private var uploadTask: Task<Void, Never>?

    init(auth: DropboxAuthService,
         client: DropboxAPIClient? = nil,
         remover: LocalFileRemover = LocalFileRemover()) {
        self.auth = auth
        self.remover = remover
        self.client = client ?? DropboxAPIClient(tokenProvider: { [auth] in
            try await auth.validAccessToken()
        })
    }

    // MARK: - 集計

    var successfulItems: [BackupItem] { items.filter { $0.status.isSuccess } }
    var failedItems: [BackupItem] { items.filter { $0.status.isFailure } }
    var skippedItems: [BackupItem] { items.filter { $0.status.isSkipped } }
    var hasRetryableFailures: Bool {
        items.contains { item in
            guard case .failed(_, let retryable) = item.status else { return false }
            return retryable
        }
    }

    /// 全体の進捗（ファイル数ではなくバイト数で重み付けする）。
    var overallProgress: Double {
        let totalBytes = items.reduce(Int64(0)) { $0 + max($1.byteSize, 1) }
        guard totalBytes > 0 else { return 0 }
        let done = items.reduce(0.0) { partial, item in
            partial + Double(max(item.byteSize, 1)) * item.status.progress
        }
        return min(1.0, done / Double(totalBytes))
    }

    var currentItem: BackupItem? {
        guard let currentItemID else { return nil }
        return items.first { $0.id == currentItemID }
    }

    // MARK: - アップロード

    /// 選択されたファイル群のアップロードを開始する。
    func start(urls: [URL]) {
        guard !urls.isEmpty else { return }
        items = urls.map(BackupItem.init(url:))
        trashOutcomes = []
        authenticationErrorMessage = nil
        run(itemIDs: items.map(\.id))
    }

    /// 失敗したファイルだけを再送する。自動リトライはせず、ユーザーの操作で呼ばれる。
    func retryFailed() {
        let ids = failedItems.map(\.id)
        guard !ids.isEmpty else { return }
        for id in ids { update(id) { $0.status = .pending } }
        run(itemIDs: ids)
    }

    /// 進行中のアップロードを中断する。
    func cancel() {
        uploadTask?.cancel()
        uploadTask = nil
        for item in items where !item.status.isFinished {
            update(item.id) { $0.status = .failed(message: "キャンセルされました。", retryable: true) }
        }
        currentItemID = nil
        phase = items.isEmpty ? .idle : .review
    }

    private func run(itemIDs: [BackupItem.ID]) {
        phase = .uploading
        uploadTask = Task { [weak self] in
            guard let self else { return }
            for id in itemIDs {
                if Task.isCancelled { break }
                await self.upload(itemID: id)
            }
            self.currentItemID = nil
            self.phase = .review
            self.uploadTask = nil
        }
    }

    private func upload(itemID: BackupItem.ID) async {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        currentItemID = itemID
        update(itemID) { $0.status = .uploading(progress: 0) }

        // アップロード直前に存在を確認する。ここで無くなっていれば「スキップ」扱いにする。
        guard FileManager.default.isReadableFile(atPath: item.url.path) else {
            update(itemID) { $0.status = .skipped(reason: "選択後にファイルが削除または移動されました。") }
            return
        }

        do {
            let metadata = try await client.upload(
                fileURL: item.url,
                remoteFolder: remoteFolder,
                // このクロージャはアップロード中だけ生きる。メインアクター隔離された
                // 自分自身は Sendable なので、不変の強参照で捕まえる
                // （弱参照だと、さらに内側の Task から捕捉変数を参照する形になり
                // 並行実行中のコードから可変の捕捉を触ることになってコンパイルできない）。
                progress: { [self] value in
                    Task { @MainActor in
                        self.update(itemID) { $0.status = .uploading(progress: value) }
                    }
                }
            )
            update(itemID) { $0.status = .succeeded(metadata: metadata) }
        } catch let error as DropboxError {
            handle(error: error, itemID: itemID)
        } catch {
            update(itemID) { $0.status = .failed(message: error.localizedDescription, retryable: false) }
        }
    }

    private func handle(error: DropboxError, itemID: BackupItem.ID) {
        let message = error.errorDescription ?? "不明なエラー"
        if error.isSkippable {
            // 削除・移動されたファイルは飛ばして次へ進み、最後にまとめて報告する。
            update(itemID) { $0.status = .skipped(reason: message) }
            return
        }
        if error.requiresReauthentication {
            authenticationErrorMessage = message
            auth.markReauthenticationRequired(reason: message)
        }
        update(itemID) { $0.status = .failed(message: message, retryable: error.isRetryable) }
    }

    // MARK: - 削除確認

    func setDeletionMark(_ marked: Bool, for id: BackupItem.ID) {
        update(id) { $0.isMarkedForDeletion = marked }
    }

    /// 成功したファイル全部に削除マークを付ける／外す。
    func markAllForDeletion(_ marked: Bool) {
        for item in successfulItems {
            update(item.id) { $0.isMarkedForDeletion = marked }
        }
    }

    var itemsMarkedForDeletion: [BackupItem] {
        successfulItems.filter(\.isMarkedForDeletion)
    }

    /// 削除マークの付いたファイルをゴミ箱へ移動する（完全削除はしない）。
    @discardableResult
    func trashMarkedFiles() -> [LocalFileRemover.Outcome] {
        let targets = itemsMarkedForDeletion
        guard !targets.isEmpty else { return [] }
        let outcomes = remover.moveToTrash(targets.map(\.url))
        trashOutcomes = outcomes
        for (item, outcome) in zip(targets, outcomes) where outcome.didSucceed {
            update(item.id) { $0.isMarkedForDeletion = false }
        }
        return outcomes
    }

    /// 結果画面を閉じて最初の状態に戻す。
    func reset() {
        uploadTask?.cancel()
        uploadTask = nil
        items = []
        trashOutcomes = []
        currentItemID = nil
        authenticationErrorMessage = nil
        phase = .idle
    }

    private func update(_ id: BackupItem.ID, _ mutate: (inout BackupItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }
}
