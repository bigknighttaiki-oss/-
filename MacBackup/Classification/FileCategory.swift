import Foundation
import UniformTypeIdentifiers

/// ファイル種別の分類。
///
/// フェーズ2（ストレージスキャン・可視化）で円グラフ・棒グラフの軸として使う想定で、
/// UI やアップロード処理から独立した単体のモジュールとして切り出してある。
/// フェーズ1では結果一覧のアイコン表示にだけ使う。
enum FileCategory: String, CaseIterable, Identifiable, Equatable, Sendable {
    case photo
    case video
    case music
    case document
    case archive
    case cache
    case application
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo: return "写真"
        case .video: return "動画"
        case .music: return "音楽"
        case .document: return "書類"
        case .archive: return "アーカイブ"
        case .cache: return "キャッシュ"
        case .application: return "アプリ"
        case .other: return "その他"
        }
    }

    /// SF Symbols 名。
    var symbolName: String {
        switch self {
        case .photo: return "photo"
        case .video: return "film"
        case .music: return "music.note"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .cache: return "trash"
        case .application: return "app.badge"
        case .other: return "doc"
        }
    }

    // MARK: - 分類

    /// 拡張子ベースの補助テーブル。UTType で判定できない
    /// 音楽制作系のファイル（プロジェクト・プラグイン等）を拾う。
    private static let extensionMap: [String: FileCategory] = [
        // 音楽制作のプロジェクト／セッション
        "logicx": .music, "band": .music, "als": .music, "flp": .music,
        "ptx": .music, "cpr": .music, "rpp": .music, "aup3": .music,
        "mid": .music, "midi": .music, "sf2": .music, "aiff": .music, "aif": .music,
        // アーカイブ
        "zip": .archive, "gz": .archive, "tgz": .archive, "bz2": .archive,
        "7z": .archive, "rar": .archive, "dmg": .archive,
        // キャッシュ・一時ファイル
        "cache": .cache, "tmp": .cache, "log": .cache,
        // 写真（RAW）
        "raw": .photo, "cr2": .photo, "cr3": .photo, "nef": .photo,
        "arw": .photo, "dng": .photo, "heic": .photo
    ]

    /// ファイル URL から種別を判定する。
    static func classify(url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()

        if ext == "app" { return .application }
        if let mapped = extensionMap[ext] { return mapped }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .photo }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .music }
            if type.conforms(to: .application) || type.conforms(to: .unixExecutable) { return .application }
            if type.conforms(to: .archive) { return .archive }
            if type.conforms(to: .text) || type.conforms(to: .pdf)
                || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation)
                || type.conforms(to: .content) {
                return .document
            }
        }

        // キャッシュ置き場に入っているものはキャッシュ扱いにする。
        let path = url.path.lowercased()
        if path.contains("/library/caches/") || path.contains("/deriveddata/") {
            return .cache
        }
        return .other
    }
}
