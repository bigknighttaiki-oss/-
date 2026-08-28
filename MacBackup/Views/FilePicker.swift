import AppKit

/// `NSOpenPanel` でバックアップ対象のファイルを選ぶ。
/// フォルダは選ばせない（フェーズ1はユーザーが選んだファイルのみが対象）。
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
}
