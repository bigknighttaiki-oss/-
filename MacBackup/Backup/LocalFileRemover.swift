import Foundation

/// ローカルファイルの削除を担当する。
///
/// 完全削除はしない。必ず `FileManager.trashItem(at:resultingItemURL:)` で
/// ゴミ箱へ移動する（誤削除からの復旧手段を残すため。これは必須要件）。
struct LocalFileRemover {

    struct Outcome: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let trashedURL: URL?
        let errorMessage: String?

        var fileName: String { url.lastPathComponent }
        var didSucceed: Bool { errorMessage == nil }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 指定されたファイルをゴミ箱に移動する。1 件失敗しても残りは続行する。
    func moveToTrash(_ urls: [URL]) -> [Outcome] {
        urls.map { url in
            var resultingURL: NSURL?
            do {
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                return Outcome(url: url, trashedURL: resultingURL as URL?, errorMessage: nil)
            } catch {
                return Outcome(url: url, trashedURL: nil, errorMessage: error.localizedDescription)
            }
        }
    }
}
