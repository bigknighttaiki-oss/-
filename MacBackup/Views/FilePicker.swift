import AppKit

/// `NSOpenPanel` でファイル／フォルダを選ぶ。
/// バックアップ（フェーズ1）はファイルのみ、スキャン（フェーズ2）はフォルダのみを選ばせる。
enum FilePicker {

    @MainActor
    static func selectFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "バックアップするファイルを選択"
        panel.prompt = "選択"
        panel.message = "Dropbox にアップロードするファイルを選んでください（複数選択できます）。"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = false

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// スキャン対象のフォルダを 1 つ選ぶ。
    @MainActor
    static func selectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "スキャンするフォルダを選択"
        panel.prompt = "スキャン"
        panel.message = "使用容量を調べるフォルダを選んでください。"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK else { return nil }
        return panel.urls.first
    }
}

