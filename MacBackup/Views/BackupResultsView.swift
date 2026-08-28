import SwiftUI

/// アップロード完了後の結果一覧。
/// 成功／失敗、autorename でリネームされた場合はリネーム後の名前、
/// そしてスキップされたファイルをまとめて出す。
struct BackupResultsView: View {
    @EnvironmentObject private var coordinator: BackupCoordinator

    @State private var isShowingDeletionSheet = false
    @State private var hasPresentedDeletionSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.block) {
                    summaryCard

                    if !coordinator.successfulItems.isEmpty {
                        successCard
                    }
                    if !coordinator.failedItems.isEmpty {
                        failureCard
                    }
                    if !coordinator.skippedItems.isEmpty {
                        skippedCard
                    }
                    if !coordinator.trashOutcomes.isEmpty {
                        trashCard
                    }
                }
                .padding(Metrics.gutter)
            }

            RowDivider()
            footer
        }
        .sheet(isPresented: $isShowingDeletionSheet) {
            DeletionConfirmationView { _ in }
                .environmentObject(coordinator)
        }
        .onAppear {
            // アップロード完了直後に一度だけ削除確認を出す。
            if !hasPresentedDeletionSheet && !coordinator.successfulItems.isEmpty {
                hasPresentedDeletionSheet = true
                isShowingDeletionSheet = true
            }
        }
    }

    // MARK: - 集計

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                Text("バックアップが終わりました")
                    .font(.title3.weight(.semibold))

                HStack(spacing: Metrics.stack) {
                    StatusChip(
                        text: "\(coordinator.successfulItems.count) 件成功",
                        systemImage: "checkmark.circle.fill",
                        tint: .green
                    )
                    if !coordinator.failedItems.isEmpty {
                        StatusChip(
                            text: "\(coordinator.failedItems.count) 件失敗",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .red
                        )
                    }
                    if !coordinator.skippedItems.isEmpty {
                        StatusChip(
                            text: "\(coordinator.skippedItems.count) 件スキップ",
                            systemImage: "forward.end.alt.fill",
                            tint: .orange
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 各セクション

    private var successCard: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header("Dropbox に保存しました", subtitle: "\(coordinator.remoteFolder)/ に入っています")

                rows(coordinator.successfulItems) { item in
                    FileRow(
                        systemImage: item.category.symbolName,
                        name: item.fileName,
                        detail: successDetail(for: item),
                        detailTint: item.wasRenamedByDropbox ? .orange : nil,
                        symbolTint: item.category.chartColor
                    ) {
                        MonoText(ByteFormatting.string(item.byteSize), font: .caption)
                    }
                }
            }
        }
    }

    private var failureCard: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header("送れなかったファイル", subtitle: "内容は Dropbox が返したメッセージのままです")

                rows(coordinator.failedItems) { item in
                    FileRow(
                        systemImage: "exclamationmark.triangle.fill",
                        name: item.fileName,
                        detail: failureMessage(for: item),
                        symbolTint: .red
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    private var skippedCard: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header("スキップしたファイル", subtitle: "アップロード中に見つからなくなったものです")

                rows(coordinator.skippedItems) { item in
                    FileRow(
                        systemImage: "forward.end.alt.fill",
                        name: item.fileName,
                        detail: skipReason(for: item),
                        symbolTint: .orange
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    private var trashCard: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header("ゴミ箱に移動しました", subtitle: "完全には消していません。必要なら戻せます")

                rows(coordinator.trashOutcomes) { outcome in
                    FileRow(
                        systemImage: outcome.didSucceed ? "trash" : "exclamationmark.triangle.fill",
                        name: outcome.fileName,
                        detail: outcome.errorMessage,
                        detailTint: outcome.errorMessage == nil ? nil : .red,
                        symbolTint: outcome.didSucceed ? nil : .red
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - 下部の操作

    private var footer: some View {
        HStack(spacing: Metrics.stack) {
            if coordinator.hasRetryableFailures {
                // 自動リトライはしない。再送はユーザーが押したときだけ。
                Button {
                    coordinator.retryFailed()
                } label: {
                    Label("失敗した分をもう一度送る", systemImage: "arrow.clockwise")
                }
            }
            Spacer()
            if !coordinator.successfulItems.isEmpty {
                Button("ローカルの削除を確認…") { isShowingDeletionSheet = true }
            }
            Button("完了") { coordinator.reset() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Metrics.gutter)
    }

    // MARK: - 部品

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title, subtitle: subtitle)
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.top, Metrics.cardPadding)
                .padding(.bottom, Metrics.tight)
        }
    }

    private func rows<Item: Identifiable, RowContent: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> RowContent
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                    .padding(.horizontal, Metrics.cardPadding)
                if item.id != items.last?.id {
                    RowDivider().padding(.leading, Metrics.cardPadding + 30)
                }
            }
        }
        .padding(.bottom, Metrics.tight)
    }

    private func successDetail(for item: BackupItem) -> String? {
        guard case .succeeded(let metadata) = item.status else { return nil }
        if item.wasRenamedByDropbox {
            // 同名ファイルがあったため Dropbox 側で連番が付いた。
            return "同名のファイルがあったので「\(metadata.name)」として保存しました"
        }
        return metadata.pathDisplay
    }

    private func failureMessage(for item: BackupItem) -> String? {
        guard case .failed(let message, _) = item.status else { return nil }
        return message
    }

    private func skipReason(for item: BackupItem) -> String? {
        guard case .skipped(let reason) = item.status else { return nil }
        return reason
    }
}
