import SwiftUI

/// アップロード中の画面。全体の進捗と、いま送っているファイルの進捗を出す。
struct UploadProgressView: View {
    @EnvironmentObject private var coordinator: BackupCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.block) {
            overallCard
            currentCard
            queueCard
        }
        .padding(Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 全体の進捗

    private var overallCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                HStack(alignment: .firstTextBaseline) {
                    Text("アップロード中")
                        .font(.headline)
                    Spacer()
                    Text("\(Int((coordinator.overallProgress * 100).rounded()))%")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                ProgressView(value: coordinator.overallProgress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(finishedCount) / \(coordinator.items.count) ファイル")
                    Spacer()
                    Text("残り \(coordinator.items.count - finishedCount) 件")
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 送信中のファイル

    @ViewBuilder
    private var currentCard: some View {
        if let current = coordinator.currentItem {
            Card {
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    HStack(spacing: Metrics.stack) {
                        Image(systemName: current.category.symbolName)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(current.category.chartColor)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            MonoText(
                                "\(ByteFormatting.string(current.byteSize)) · \(Int((current.status.progress * 100).rounded()))%",
                                font: .caption
                            )
                        }
                        Spacer(minLength: 0)
                    }

                    ProgressView(value: current.status.progress)
                        .progressViewStyle(.linear)
                }
            }
        }
    }

    // MARK: - 待ち行列

    private var queueCard: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("ファイル", subtitle: "上から順に送ります")
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.top, Metrics.cardPadding)
                    .padding(.bottom, Metrics.tight)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(coordinator.items) { item in
                            FileRow(
                                systemImage: item.category.symbolName,
                                name: item.fileName,
                                symbolTint: item.category.chartColor
                            ) {
                                UploadStatusLabel(status: item.status)
                            }
                            .padding(.horizontal, Metrics.cardPadding)

                            if item.id != coordinator.items.last?.id {
                                RowDivider().padding(.leading, Metrics.cardPadding + 30)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)

                RowDivider()

                HStack {
                    Spacer()
                    Button("中断", role: .cancel) { coordinator.cancel() }
                }
                .padding(Metrics.cardPadding)
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
