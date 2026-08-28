import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: DropboxAuthService
    @EnvironmentObject private var coordinator: BackupCoordinator

    @State private var isShowingSettings = false
    @State private var authErrorMessage: String?
    @State private var isShowingAuthAlert = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 460)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(auth)
                .environmentObject(coordinator)
        }
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

    private var header: some View {
        HStack {
            Label("Mac Backup", systemImage: "externaldrive.badge.icloud")
                .font(.headline)
            Spacer()
            ConnectionBadge(state: auth.state)
            Button {
                isShowingSettings = true
            } label: {
                Label("設定", systemImage: "gearshape")
            }
            .help("Dropbox 連携の状態やアップロード先を確認する")
        }
        .padding(12)
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
                    Button("設定を開く") { isShowingSettings = true }
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

/// Dropbox 連携状態の小さなバッジ。
struct ConnectionBadge: View {
    let state: DropboxAuthService.State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch state {
        case .signedIn: return .green
        case .authenticating: return .yellow
        case .needsReauthentication: return .orange
        case .signedOut, .notConfigured: return .secondary
        }
    }

    private var text: String {
        switch state {
        case .signedIn: return "Dropbox 連携済み"
        case .authenticating: return "サインイン中…"
        case .needsReauthentication: return "再認証が必要"
        case .signedOut: return "未サインイン"
        case .notConfigured: return "App key 未設定"
        }
    }
}
