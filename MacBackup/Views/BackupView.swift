import Combine
import SwiftUI

/// フェーズ1: ファイルを選んで Dropbox にアップロードする画面。
struct BackupView: View {
    @EnvironmentObject private var auth: DropboxAuthService
    @EnvironmentObject private var coordinator: BackupCoordinator

    /// 設定画面を開くよう親に依頼する。
    var onOpenSettings: () -> Void

    @State private var authErrorMessage: String?
    @State private var isShowingAuthAlert = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Dropbox の認証が必要です", isPresented: $isShowingAuthAlert) {
                Button("再認証") { Task { await signIn() } }
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(authErrorMessage ?? "Dropbox に再度サインインしてください。")
            }
            .onReceive(coordinator.$authenticationErrorMessage.compactMap { $0 }) { message in
                authErrorMessage = message
                isShowingAuthAlert = true
            }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .idle:
            startView
        case .uploading:
            UploadProgressView()
        case .review:
            BackupResultsView()
        }
    }

    // MARK: - 開始画面

    @ViewBuilder
    private var startView: some View {
        switch auth.state {
        case .signedIn:
            EmptyState(
                systemImage: "arrow.up.circle",
                title: "バックアップするファイルを選ぶ",
                message: "写真や音楽制作のファイルを Dropbox に退避します。複数まとめて選べます。"
            ) {
                VStack(spacing: Metrics.block) {
                    Button {
                        let urls = FilePicker.selectFiles()
                        if !urls.isEmpty { coordinator.start(urls: urls) }
                    } label: {
                        Label("ファイルを選択", systemImage: "plus")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    destinationChip
                }
            }

        case .notConfigured:
            EmptyState(
                systemImage: "key.slash",
                title: "Dropbox の App key が未設定です",
                message: "Dropbox Developer Console で取得した App key を、環境変数か設定ファイルから読み込ませてください。"
            ) {
                Button("設定を開く", action: onOpenSettings)
                    .controlSize(.large)
            }

        case .authenticating:
            EmptyState(
                systemImage: "arrow.triangle.2.circlepath",
                title: "Dropbox にサインインしています",
                message: "ブラウザで認証を済ませてください。"
            ) {
                ProgressView()
                    .controlSize(.small)
            }

        case .needsReauthentication(let reason):
            EmptyState(
                systemImage: "exclamationmark.triangle",
                title: "再認証が必要です",
                message: reason
            ) {
                Button("Dropbox に再サインイン") { Task { await signIn() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

        case .signedOut:
            EmptyState(
                systemImage: "person.crop.circle.badge.plus",
                title: "Dropbox に接続する",
                message: "バックアップ先の Dropbox アカウントにサインインしてください。"
            ) {
                Button("Dropbox にサインイン") { Task { await signIn() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    /// アップロード先を示す小さな表示。
    private var destinationChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .symbolRenderingMode(.hierarchical)
            Text("アップロード先")
                .foregroundStyle(.secondary)
            Text("\(coordinator.remoteFolder)/")
                .monospaced()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Palette.surface)
        )
        .overlay(
            Capsule().strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    private func signIn() async {
        do {
            try await auth.signIn()
        } catch DropboxError.cancelled {
            // ユーザーが自分で閉じた場合は何も出さない。
        } catch {
            authErrorMessage = error.localizedDescription
            isShowingAuthAlert = true
        }
    }
}
