import SwiftUI

/// アップロード完了後の結果一覧。
/// 成功／失敗、autorename でリネームされた場合はリネーム後の名前、
/// そしてスキップされたファイルをまとめて出す。
struct BackupResultsView: View {
    @EnvironmentObject private var coordinator: BackupCoordinator

    @State private var isShowingDeletionSheet = false
    @State private var hasPresentedDeletionSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary

            List {
                if !coordinator.successfulItems.isEmpty {
                    Section("成功 (\(coordinator.successfulItems.count))") {
                        ForEach(coordinator.successfulItems) { item in
                            successRow(item)
                        }
                    }
                }
                if !coordinator.failedItems.isEmpty {
                    Section("失敗 (\(coordinator.failedItems.count))") {
                        ForEach(coordinator.failedItems) { item in
                            failureRow(item)
                        }
                    }
                }
                if !coordinator.skippedItems.isEmpty {
                    Section("スキップされたファイル (\(coordinator.skippedItems.count))") {
                        ForEach(coordinator.skippedItems) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fileName).lineLimit(1).truncationMode(.middle)
                                if case .skipped(let reason) = item.status {
                                    Text(reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !coordinator.trashOutcomes.isEmpty {
                    Section("ゴミ箱に移動") {
                        ForEach(coordinator.trashOutcomes) { outcome in
                            HStack {
                                Image(systemName: outcome.didSucceed ? "trash" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(outcome.didSucceed ? Color.secondary : Color.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(outcome.fileName).lineLimit(1).truncationMode(.middle)
                                    if let message = outcome.errorMessage {
                                        Text(message).font(.caption).foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                if coordinator.hasRetryableFailures {
                    // 自動リトライはしない。再送はユーザーが押したときだけ。
                    Button {
                        coordinator.retryFailed()
                    } label: {
                        Label("失敗したファイルをリトライ", systemImage: "arrow.clockwise")
                    }
                }
                Spacer()
                if !coordinator.successfulItems.isEmpty {
                    Button("ローカルファイルの削除を確認…") { isShowingDeletionSheet = true }
                }
                Button("完了") { coordinator.reset() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
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

    private var summary: some View {
        HStack(spacing: 16) {
            Label("\(coordinator.successfulItems.count) 件成功", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if !coordinator.failedItems.isEmpty {
                Label("\(coordinator.failedItems.count) 件失敗", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if !coordinator.skippedItems.isEmpty {
                Label("\(coordinator.skippedItems.count) 件スキップ", systemImage: "forward.end.alt.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.subheadline)
    }

    private func successRow(_ item: BackupItem) -> some View {
        HStack {
            Image(systemName: item.category.symbolName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName).lineLimit(1).truncationMode(.middle)
                if case .succeeded(let metadata) = item.status {
                    if item.wasRenamedByDropbox {
                        // 同名ファイルがあったため Dropbox 側で連番が付いた。
                        Text("Dropbox 上の名前: \(metadata.name)（同名ファイルがあったためリネーム）")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(metadata.pathDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            Text(ByteFormatting.string(item.byteSize))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func failureRow(_ item: BackupItem) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName).lineLimit(1).truncationMode(.middle)
                if case .failed(let message, _) = item.status {
                    // Dropbox が返したメッセージをそのまま出す。
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }
}
