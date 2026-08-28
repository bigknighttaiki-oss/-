import SwiftUI

/// アップロード中の画面。全体の進捗と、いま送っているファイルの進捗を出す。
struct UploadProgressView: View {
    @EnvironmentObject private var coordinator: BackupCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("全体の進捗")
                    .font(.headline)
                ProgressView(value: coordinator.overallProgress)
                Text("\(finishedCount) / \(coordinator.items.count) ファイル")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let current = coordinator.currentItem {
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView(value: current.status.progress)
                    Text("\(ByteFormatting.string(current.byteSize)) · \(Int(current.status.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            List(coordinator.items) { item in
                HStack {
                    Image(systemName: item.category.symbolName)
                        .foregroundStyle(.secondary)
                    Text(item.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    StatusLabel(status: item.status)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                Button("中断", role: .cancel) { coordinator.cancel() }
            }
        }
        .padding()
    }

    private var finishedCount: Int {
        coordinator.items.filter { $0.status.isFinished }.count
    }
}

struct StatusLabel: View {
    let status: BackupItem.Status

    var body: some View {
        switch status {
        case .pending:
            Text("待機中").font(.caption).foregroundStyle(.secondary)
        case .uploading(let progress):
            Text("\(Int(progress * 100))%").font(.caption).monospacedDigit()
        case .succeeded:
            Label("完了", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
        case .failed:
            Label("失敗", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        case .skipped:
            Label("スキップ", systemImage: "forward.end.alt.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.orange)
        }
    }
}
