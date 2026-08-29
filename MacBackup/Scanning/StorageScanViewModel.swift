import Foundation

/// ストレージスキャン画面の状態を持つ。
/// 走査そのものは `Task.detached` でメインスレッドの外に出す。
@MainActor
final class StorageScanViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case scanning(StorageScanner.Progress)
        case finished(ScanResult)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var includesHiddenFiles: Bool = false
    /// 直近にスキャンしたフォルダ。再スキャンに使う。
    @Published private(set) var lastRoot: URL?
    /// デモ表示中かどうか。true の間はディスクを走査しない。
    @Published private(set) var isDemoSession = false

    private var scanTask: Task<Void, Never>?

    var result: ScanResult? {
        if case .finished(let result) = state { return result }
        return nil
    }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    /// サンプルデータでスキャンの流れを再現する。
    ///
    /// 実際のフォルダは走査しないので、フォルダを選ばなくても結果画面を確認できる。
    func startDemo() {
        scanTask?.cancel()
        isDemoSession = true
        lastRoot = nil
        state = .scanning(StorageScanner.Progress(currentPath: DemoContent.scanningPaths[0]))

        let result = DemoContent.scanResult
        scanTask = Task { [self] in
            let steps = 16
            for step in 1...steps {
                if Task.isCancelled { return }
                let ratio = Double(step) / Double(steps)
                state = .scanning(StorageScanner.Progress(
                    filesScanned: Int(Double(result.fileCount) * ratio),
                    bytesScanned: Int64(Double(result.totalBytes) * ratio),
                    currentPath: DemoContent.scanningPaths[step % DemoContent.scanningPaths.count]
                ))
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            if Task.isCancelled { return }
            state = .finished(result)
            scanTask = nil
        }
    }

    /// フォルダを選んでスキャンする。
    func chooseFolderAndScan() {
        guard let root = FilePicker.selectFolder() else { return }
        scan(root: root)
    }

    /// 直近と同じフォルダをもう一度スキャンする。
    func rescan() {
        guard let lastRoot else { return }
        scan(root: lastRoot)
    }

    func scan(root: URL) {
        scanTask?.cancel()
        isDemoSession = false
        lastRoot = root
        state = .scanning(StorageScanner.Progress(currentPath: root.path))

        // 並行実行されるクロージャに渡すので、可変の var ではなく let で組み立てる。
        let options = StorageScanner.Options(includesHiddenFiles: includesHiddenFiles)

        // メインアクター隔離された自分自身は Sendable なので、不変の強参照で捕まえる。
        // 弱参照にすると、内側の Task が捕捉変数を参照する形になりコンパイルできない。
        // タスクは終了時に解放されるので、参照が残り続けることはない。
        scanTask = Task { [self] in
            // 途中経過はバックグラウンドから届くので、メインアクターに載せ替える。
            let update: @Sendable (StorageScanner.Progress) -> Void = { progress in
                Task { @MainActor in
                    guard self.isScanning else { return }
                    self.state = .scanning(progress)
                }
            }

            let work = Task.detached(priority: .utility) {
                try StorageScanner(options: options).scan(root: root, onProgress: update)
            }

            do {
                // detached したタスクは親のキャンセルを引き継がないので、明示的に伝える。
                let result = try await withTaskCancellationHandler {
                    try await work.value
                } onCancel: {
                    work.cancel()
                }
                guard !Task.isCancelled else { return }
                self.state = .finished(result)
            } catch {
                if error is CancellationError || (error as? StorageScanner.ScanError) == .cancelled {
                    self.state = .idle
                } else if !Task.isCancelled {
                    self.state = .failed(error.localizedDescription)
                }
            }
            self.scanTask = nil
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isDemoSession = false
        state = .idle
    }

    func reset() {
        cancel()
        lastRoot = nil
    }
}
