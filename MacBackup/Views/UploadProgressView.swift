import SwiftUI

/// アップロード中の画面。中央のリングが全体の進捗、その下が 1 ファイルずつの状態。
struct UploadProgressView: View {
    @EnvironmentObject private var coordinator: BackupCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.block) {
                hero
                queueCard
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        Card(padding: 24) {
            VStack(spacing: Metrics.block) {
                RadialGauge(
                    segments: [
                        .init(id: "done", value: max(coordinator.overallProgress, 0.001), color: .accentColor),
                        .init(id: "rest", value: max(1 - coordinator.overallProgress, 0.001),
                              color: Palette.border.opacity(0.9))
                    ]
                ) {
                    GaugeReadout(
                        value: "\(Int((coordinator.overallProgress * 100).rounded()))%",
                        caption: "アップロード中",
                        note: "\(finishedCount) / \(coordinator.items.count) ファイル"
                    )
                }
                .frame(width: 240, height: 240)

                if let current = coordinator.currentItem {
                    VStack(spacing: Metrics.tight) {
                        Text(current.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        MonoText(
                            "\(ByteFormatting.string(current.byteSize)) · \(Int((current.status.progress * 100).rounded()))%",
                            font: .caption
                        )
                    }
                    .frame(maxWidth: 460)
                }

                Button("中断", role: .cancel) { coordinator.cancel() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var queueCard: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("ファイル", subtitle: "上から順に送ります")
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.top, Metrics.cardPadding)
                    .padding(.bottom, Metrics.tight)

                ForEach(coordinator.items) { item in
                    HStack(spacing: Metrics.stack) {
                        CategoryBadge(category: item.category, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            MonoText(ByteFormatting.string(item.byteSize), font: .caption)
                        }
                        Spacer(minLength: Metrics.stack)
                        UploadStatusLabel(status: item.status)
                    }
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 8)

                    if item.id != coordinator.items.last?.id {
                        RowDivider().padding(.leading, 52)
                    }
                }
                .padding(.bottom, Metrics.tight)
            }
        }
    }

    private var finishedCount: Int {
        coordinator.items.filter { $0.status.isFinished }.count
    }
}

/// 1 ファイルの状態表示。色に加えて記号か数値でも状態が分かるようにする。
struct UploadStatusLabel: View {
    let status: BackupItem.Status

    var body: some View {
        switch status {
        case .pending:
            Text("待機中")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .uploading(let progress):
            HStack(spacing: 7) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 68)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        case .succeeded:
            StatusChip(text: "完了", systemImage: "checkmark.circle.fill", tint: .green)
        case .failed:
            StatusChip(text: "失敗", systemImage: "exclamationmark.triangle.fill", tint: .red)
        case .skipped:
            StatusChip(text: "スキップ", systemImage: "forward.end.alt.fill", tint: .orange)
        }
    }
}
