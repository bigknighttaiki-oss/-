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

    private var startView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.up.doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("写真や音楽制作のファイルを Dropbox に退避します。")
                .foregroundStyle(.secondary)
            Text("アップロード先: \(coordinator.remoteFolder)/")
                .font(.callout)
                .foregroundStyle(.tertiary)

            switch auth.state {
            case .notConfigured:
                VStack(spacing: 8) {
                    Text("Dropbox の App key が設定されていません。")
                        .foregroundStyle(.orange)
                    Button("設定を開く", action: onOpenSettings)
                }
            case .signedIn:
                Button {
                    let urls = FilePicker.selectFiles()
                    if !urls.isEmpty { coordinator.start(urls: urls) }
                } label: {
                    Label("バックアップ", systemImage: "square.and.arrow.up")
                        .frame(minWidth: 160)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            case .authenticating:
                ProgressView("Dropbox にサインインしています…")
            case .signedOut, .needsReauthentication:
                VStack(spacing: 8) {
                    if case .needsReauthentication(let reason) = auth.state {
                        Text(reason)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    Button("Dropbox にサインイン") { Task { await signIn() } }
                        .controlSize(.large)
                }
            }
            Spacer()
        }
        .padding()
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
