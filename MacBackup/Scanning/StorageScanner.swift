import Foundation

/// 指定フォルダ以下を走査して、種別ごとの使用容量を集計する。
///
/// UI からは独立させてあり、同期的に走る。呼び出し側が `Task.detached` などで
/// メインスレッド外に出して使う前提。`Task.isCancelled` を見て中断できる。
struct StorageScanner {

    /// 走査中の途中経過。
    struct Progress: Equatable, Sendable {
        var filesScanned: Int = 0
        var bytesScanned: Int64 = 0
        /// いま見ているパス（表示用）。
        var currentPath: String = ""
    }

    struct Options: Equatable, Sendable {
        /// 隠しファイルを数えるか。
        var includesHiddenFiles: Bool = false
        /// 「大きいファイル」一覧に載せる件数。
        var largestFileCount: Int = 100
        /// 途中経過を通知する間隔（ファイル数）。
        var progressInterval: Int = 256

        static let `default` = Options()
    }

    enum ScanError: LocalizedError, Equatable {
        case notADirectory(URL)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notADirectory(let url):
                return "フォルダではありません: \(url.path)"
            case .cancelled:
                return "スキャンを中断しました。"
            }
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    let fileManager: FileManager
    let options: Options

    init(fileManager: FileManager = .default, options: Options = .default) {
        self.fileManager = fileManager
        self.options = options
    }

    /// `root` 以下を走査する。
    /// - Parameter onProgress: 一定件数ごとに呼ばれる。呼び出しスレッドはこのメソッドと同じ。
    func scan(root: URL, onProgress: @Sendable (Progress) -> Void = { _ in }) throws -> ScanResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScanError.notADirectory(root)
        }

        var enumeratorOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includesHiddenFiles {
            enumeratorOptions.insert(.skipsHiddenFiles)
        }

        var unreadablePaths: [String] = []
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Self.resourceKeys,
            options: enumeratorOptions,
            errorHandler: { url, _ in
                // 読めないものは記録して先へ進む。
                unreadablePaths.append(url.path)
                return true
            }
        )

        var progress = Progress()
        var totals: [FileCategory: (bytes: Int64, count: Int)] = [:]
        var largest = LargestFiles(capacity: options.largestFileCount)

        while let url = enumerator?.nextObject() as? URL {
            if Task.isCancelled { throw ScanError.cancelled }

            guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)) else {
                unreadablePaths.append(url.path)
                continue
            }
            // シンボリックリンクは実体を二重に数えないよう飛ばす。
            if values.isSymbolicLink == true { continue }

            let isPackage = (values.isPackage == true) && (values.isDirectory == true)
            if values.isDirectory == true && !isPackage { continue }

            // パッケージ（.app や .logicx など）は 1 つのファイルとして扱い、
            // 中身の合計サイズを持たせる。
            let size = isPackage ? directorySize(of: url) : Self.fileSize(from: values)
            let file = ScannedFile(
                url: url,
                byteSize: size,
                category: FileCategory.classify(url: url),
                modifiedAt: values.contentModificationDate
            )

            var entry = totals[file.category] ?? (0, 0)
            entry.bytes += size
            entry.count += 1
            totals[file.category] = entry

            largest.insert(file)

            progress.filesScanned += 1
            progress.bytesScanned += size
            progress.currentPath = url.path
            if progress.filesScanned % options.progressInterval == 0 {
                onProgress(progress)
            }
        }
        onProgress(progress)

        let totalBytes = totals.values.reduce(Int64(0)) { $0 + $1.bytes }
        let usages = totals
            .map { category, entry in
                CategoryUsage(
                    category: category,
                    byteSize: entry.bytes,
                    fileCount: entry.count,
                    share: totalBytes > 0 ? Double(entry.bytes) / Double(totalBytes) : 0
                )
            }
            .sorted { $0.byteSize > $1.byteSize }

        return ScanResult(
            root: root,
            scannedAt: Date(),
            totalBytes: totalBytes,
            fileCount: progress.filesScanned,
            usages: usages,
            largestFiles: largest.sortedDescending(),
            unreadablePaths: unreadablePaths,
            volume: Self.volumeUsage(of: root)
        )
    }

    /// パッケージの中身を合計する。パッケージ内はさらに掘らずに全て数える。
    private func directorySize(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            if Task.isCancelled { return total }
            guard let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Self.fileSize(from: values)
        }
        return total
    }

    /// ディスク上の占有サイズを優先して取る（無ければ論理サイズ）。
    private static func fileSize(from values: URLResourceValues) -> Int64 {
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let allocated = values.fileAllocatedSize { return Int64(allocated) }
        if let logical = values.fileSize { return Int64(logical) }
        return 0
    }

    private static func volumeUsage(of url: URL) -> VolumeUsage? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return nil }

        guard let total = values.volumeTotalCapacity else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return VolumeUsage(totalBytes: Int64(total), availableBytes: Int64(available))
    }
}

/// 容量の大きいファイル上位 N 件だけを保持する小さなバッファ。
/// 全ファイルを配列に溜めないので、数十万ファイルを走査してもメモリが膨らまない。
private struct LargestFiles {
    private var items: [ScannedFile] = []
    private let capacity: Int
    /// 保持中の最小サイズとその位置。毎回全走査しないようキャッシュする。
    private var minIndex: Int = 0
    private var minSize: Int64 = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        items.reserveCapacity(self.capacity)
    }

    mutating func insert(_ file: ScannedFile) {
        if items.count < capacity {
            items.append(file)
            if items.count == capacity { recomputeMinimum() }
            return
        }
        guard file.byteSize > minSize else { return }
        items[minIndex] = file
        recomputeMinimum()
    }

    private mutating func recomputeMinimum() {
        guard let index = items.indices.min(by: { items[$0].byteSize < items[$1].byteSize }) else { return }
        minIndex = index
        minSize = items[index].byteSize
    }

    func sortedDescending() -> [ScannedFile] {
        items.sorted { $0.byteSize > $1.byteSize }
    }
}
