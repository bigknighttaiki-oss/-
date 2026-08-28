import SwiftUI

/// 設定画面。
/// フェーズ1ではアップロード先は固定だが、将来変更できるよう UI の土台だけ用意してある。
struct SettingsView: View {
    @EnvironmentObject private var auth: DropboxAuthService
    @EnvironmentObject private var coordinator: BackupCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var accountEmail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("設定")
                .font(.title2.bold())

            GroupBox("Dropbox 連携") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ConnectionBadge(state: auth.state)
                        Spacer()
                    }
                    if let accountEmail {
                        Text("アカウント: \(accountEmail)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if case .needsReauthentication(let reason) = auth.state {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if case .notConfigured = auth.state {
                        appKeyInstructions
                    }
                    HStack {
                        Button("再認証") { Task { await signIn() } }
                            .disabled(auth.state == .notConfigured)
                        Button("サインアウト") { auth.signOut(); accountEmail = nil }
                            .disabled(!auth.state.isSignedIn)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("アップロード先") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("フォルダ")
                        // フェーズ1では固定。将来ここを編集可能にする。
                        TextField("", text: .constant(coordinator.remoteFolder))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                    }
                    Text("フェーズ1ではアップロード先は \(AppConfig.defaultRemoteFolder)/ に固定されています。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 460)
        .task { await loadAccount() }
    }

    private var appKeyInstructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dropbox の App key が見つかりません。次のいずれかを設定してください。")
                .font(.callout)
                .foregroundStyle(.orange)
            Text("""
            1. 環境変数 DROPBOX_APP_KEY
            2. \(AppConfig.userConfigURL.path) の AppKey
            3. アプリバンドル内の DropboxConfig.plist の AppKey
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }

    private func signIn() async {
        errorMessage = nil
        do {
            try await auth.signIn()
            await loadAccount()
        } catch DropboxError.cancelled {
            // 何も出さない。
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAccount() async {
        guard auth.state.isSignedIn else { return }
        let auth = self.auth
        let client = DropboxAPIClient(tokenProvider: { try await auth.validAccessToken() })
        accountEmail = try? await client.currentAccountEmail()
    }
}
