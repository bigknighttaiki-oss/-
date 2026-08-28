import Foundation

/// スキャンで見つかった 1 ファイル（またはパッケージ 1 個）。
struct ScannedFile: Identifiable, Equatable, Sendable {
    var id: URL { url }
    let url: URL
    /// ディスク上の占有サイズ（バイト）。パッケージは中身の合計。
    let byteSize: Int64
    let category: FileCategory
    let modifiedAt: Date?

    var fileName: String { url.lastPathComponent }
    var parentPath: String { url.deletingLastPathComponent().path }
}

/// 種別ごとの集計。円グラフ・棒グラフの 1 系列にあたる。
struct CategoryUsage: Identifiable, Equatable, Sendable {
    var id: FileCategory { category }
    let category: FileCategory
    let byteSize: Int64
    let fileCount: Int
    /// スキャン対象全体に対する割合（0.0〜1.0）。
    let share: Double
}

/// スキャン対象が置かれているボリュームの容量。
struct VolumeUsage: Equatable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedShare: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

/// スキャン 1 回分の結果。
struct ScanResult: Equatable, Sendable {
    let root: URL
    let scannedAt: Date
    let totalBytes: Int64
    let fileCount: Int
    /// 種別ごとの集計。容量の大きい順。
    let usages: [CategoryUsage]
    /// 容量の大きいファイル上位（削除判断の入口）。
    let largestFiles: [ScannedFile]
    /// 権限などで読めなかったパス。
    let unreadablePaths: [String]
    let volume: VolumeUsage?

    static let empty = ScanResult(
        root: URL(fileURLWithPath: "/"),
        scannedAt: .distantPast,
        totalBytes: 0,
        fileCount: 0,
        usages: [],
        largestFiles: [],
        unreadablePaths: [],
        volume: nil
    )

    /// 指定した種別の集計を返す（無ければ 0 件の集計）。
    func usage(for category: FileCategory) -> CategoryUsage {
        usages.first { $0.category == category }
            ?? CategoryUsage(category: category, byteSize: 0, fileCount: 0, share: 0)
    }
}
