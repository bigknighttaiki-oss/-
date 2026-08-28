import SwiftUI

/// アップロード成功後に出す、ローカルファイルの削除確認。
///
/// - 既定は「残す」。誤操作で削除されないよう、チェックは全て外した状態で開く。
/// - 削除は完全削除ではなくゴミ箱への移動（`FileManager.trashItem`）。
struct DeletionConfirmationView: View {
    @EnvironmentObject private var coordinator: BackupCoordinator
    @Environment(\.dismiss) private var dismiss

    /// ゴミ箱移動の結果を親に伝える。
    var onTrashed: ([LocalFileRemover.Outcome]) -> Void

    private var items: [BackupItem] { coordinator.successfulItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dropbox へのアップロードが完了しました。ローカルのファイルを削除しますか？")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text("削除したファイルはゴミ箱に移動します。完全には消さないので、必要になったらゴミ箱から戻せます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("すべて削除") { coordinator.markAllForDeletion(true) }
                Button("すべて残す") { coordinator.markAllForDeletion(false) }
                Spacer()
                Text("\(coordinator.itemsMarkedForDeletion.count) / \(items.count) 件を削除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ファイルごとの個別選択。
            List(items) { item in
                Toggle(isOn: Binding(
                    get: { item.isMarkedForDeletion },
                    set: { coordinator.setDeletionMark($0, for: item.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(ByteFormatting.string(item.byteSize)) · \(item.url.deletingLastPathComponent().path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(minHeight: 180)

            HStack {
                Spacer()
                Button("削除する", role: .destructive) {
                    onTrashed(coordinator.trashMarkedFiles())
                    dismiss()
                }
                .disabled(coordinator.itemsMarkedForDeletion.isEmpty)

                // 既定のボタンは「残す」。Return キーでもこちらが選ばれる。
                Button("残す") {
                    coordinator.markAllForDeletion(false)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 420)
    }
}
