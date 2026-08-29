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
    private var markedCount: Int { coordinator.itemsMarkedForDeletion.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.block) {
            headline
            fileList
            actions
        }
        .padding(Metrics.gutter)
        .frame(width: 540, height: 460)
        .background(Palette.ground)
    }

    private var headline: some View {
        HStack(alignment: .top, spacing: Metrics.block) {
            Image(systemName: "trash.circle")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: Metrics.tight) {
                Text("ローカルのファイルを削除しますか？")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Dropbox へのアップロードは完了しています。削除するとゴミ箱に移動します。完全には消さないので、必要になったらゴミ箱から戻せます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fileList: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: Metrics.stack) {
                    Button("すべて選択") { coordinator.markAllForDeletion(true) }
                    Button("すべて解除") { coordinator.markAllForDeletion(false) }
                    Spacer()
                    Text("\(markedCount) / \(items.count) 件を削除")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(markedCount > 0 ? Color.primary : Color.secondary)
                }
                .controlSize(.small)
                .padding(Metrics.cardPadding)

                RowDivider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            Toggle(isOn: Binding(
                                get: { item.isMarkedForDeletion },
                                set: { coordinator.setDeletionMark($0, for: item.id) }
                            )) {
                                HStack(spacing: Metrics.stack) {
                                    Image(systemName: item.category.symbolName)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(item.category.chartColor)
                                        .frame(width: 20)
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
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(.horizontal, Metrics.cardPadding)
                            .padding(.vertical, 7)

                            if item.id != items.last?.id {
                                RowDivider().padding(.leading, Metrics.cardPadding)
                            }
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Metrics.stack) {
            Spacer()
            Button("ゴミ箱に移動", role: .destructive) {
                onTrashed(coordinator.trashMarkedFiles())
                dismiss()
            }
            .disabled(markedCount == 0)

            // 既定のボタンは「残す」。Return キーでもこちらが選ばれる。
            Button("残す") {
                coordinator.markAllForDeletion(false)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}
