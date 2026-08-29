import Foundation

/// デモ表示に使うサンプルデータ。
///
/// Dropbox のアプリ登録やフォルダ選択をしなくても全画面を触れるようにするためのもの。
/// ここに出てくるパスは実在しない。デモ中はディスクにもネットワークにも一切触れない。
enum DemoContent {

    /// デモであることが分かるよう、実在しない場所を指す。
    private static let root = URL(fileURLWithPath: "/Users/あなた/Music/デモ", isDirectory: true)

    private static func url(_ name: String, in folder: String = "Bounces") -> URL {
        root.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
    }

    // MARK: - バックアップ

    /// アップロードのデモに使うファイル。
    /// 成功・リネーム・失敗・スキップが一通り出るよう選んである。
    static var backupItems: [BackupItem] {
        [
            BackupItem(demoURL: url("デモ_ミックス_v12.wav"), byteSize: 1_288_490_188),
            BackupItem(demoURL: url("ジャケット案.png", in: "Artwork"), byteSize: 14_889_779),
            BackupItem(demoURL: url("ライブ映像_2026-05-12.mov", in: "Video"), byteSize: 6_549_123_072),
            BackupItem(demoURL: url("下書き_02.logicx", in: "Logic"), byteSize: 3_435_973_836)
        ]
    }

    /// Dropbox が返したことにするメタデータ。3 番目のファイルは同名衝突でリネームされる。
    static func metadata(for item: BackupItem, renamed: Bool) -> DropboxFileMetadata {
        let name = renamed
            ? item.url.deletingPathExtension().lastPathComponent
                + " (1)." + item.url.pathExtension
            : item.fileName
        return DropboxFileMetadata(
            name: name,
            pathDisplay: "\(AppConfig.defaultRemoteFolder)/\(name)",
            size: item.byteSize
        )
    }

    static let failureMessage =
        "ネットワークエラー: インターネット接続がオフラインのようです。"
    static let skipReason =
        "選択後にファイルが削除または移動されました。"

    // MARK: - ストレージ

    /// 種別ごとの容量（バイト）。音楽制作をしている人の「ミュージック」フォルダを想定。
    private static let categoryBytes: [(FileCategory, Int64, Int)] = [
        (.music,       126_913_444_741, 21_480),
        (.video,        45_204_953_333,    612),
        (.photo,        26_628_940_431, 15_904),
        (.archive,      13_314_470_215,    188),
        (.document,      9_556_302_233,  6_021),
        (.cache,         5_476_083_302,  3_402),
        (.application,   2_469_606_195,     31),
        (.other,           858_993_459,    474)
    ]

    static var scanResult: ScanResult {
        let total = categoryBytes.reduce(Int64(0)) { $0 + $1.1 }
        let usages = categoryBytes.map { category, bytes, count in
            CategoryUsage(
                category: category,
                byteSize: bytes,
                fileCount: count,
                share: total > 0 ? Double(bytes) / Double(total) : 0
            )
        }
        return ScanResult(
            root: URL(fileURLWithPath: "/Users/あなた/Music"),
            scannedAt: Date(),
            totalBytes: total,
            fileCount: categoryBytes.reduce(0) { $0 + $1.2 },
            usages: usages.sorted { $0.byteSize > $1.byteSize },
            largestFiles: largestFiles,
            unreadablePaths: ["/Users/あなた/Music/Audio Music Apps/Databases"],
            volume: VolumeUsage(totalBytes: 1_068_010_045_440, availableBytes: 201_115_074_560)
        )
    }

    private static var largestFiles: [ScannedFile] {
        let day: TimeInterval = 60 * 60 * 24
        return [
            ScannedFile(url: url("Session 04 Master.logicx", in: "Logic"),
                        byteSize: 9_019_431_321, category: .music,
                        modifiedAt: Date().addingTimeInterval(-3 * day)),
            ScannedFile(url: url("ライブ映像_2026-05-12.mov", in: "Video"),
                        byteSize: 6_549_123_072, category: .video,
                        modifiedAt: Date().addingTimeInterval(-21 * day)),
            ScannedFile(url: url("Sample Library Vol.3.zip", in: "Samples"),
                        byteSize: 5_046_586_573, category: .archive,
                        modifiedAt: Date().addingTimeInterval(-96 * day)),
            ScannedFile(url: url("下書き_2025_全部入り.logicx", in: "Logic/Archive"),
                        byteSize: 3_435_973_836, category: .music,
                        modifiedAt: Date().addingTimeInterval(-244 * day)),
            ScannedFile(url: url("マスタリング前_全曲.wav"),
                        byteSize: 2_147_483_648, category: .music,
                        modifiedAt: Date().addingTimeInterval(-12 * day)),
            ScannedFile(url: url("アートワーク_入稿用.psd", in: "Artwork"),
                        byteSize: 1_610_612_736, category: .photo,
                        modifiedAt: Date().addingTimeInterval(-40 * day)),
            ScannedFile(url: url("リハーサル_2026-04-02.mov", in: "Video"),
                        byteSize: 1_395_864_371, category: .video,
                        modifiedAt: Date().addingTimeInterval(-149 * day)),
            ScannedFile(url: url("音源候補_まとめ.zip", in: "Samples"),
                        byteSize: 1_073_741_824, category: .archive,
                        modifiedAt: Date().addingTimeInterval(-61 * day))
        ]
    }

    /// 走査中の表示に使う、それらしいパス。
    static let scanningPaths = [
        "/Users/あなた/Music/Logic/Session 04 Master.logicx",
        "/Users/あなた/Music/Samples/Sample Library Vol.3.zip",
        "/Users/あなた/Music/Video/ライブ映像_2026-05-12.mov",
        "/Users/あなた/Music/Bounces/デモ_ミックス_v12.wav",
        "/Users/あなた/Music/Artwork/アートワーク_入稿用.psd"
    ]
}
