import SwiftUI

/// アプリのシェル。サイドバーで機能を切り替える。
struct ContentView: View {
    @EnvironmentObject private var auth: DropboxAuthService
    @EnvironmentObject private var coordinator: BackupCoordinator

    enum Feature: String, CaseIterable, Identifiable {
        case backup
        case storage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .backup: return "バックアップ"
            case .storage: return "ストレージ"
            }
        }

        var symbolName: String {
            switch self {
            case .backup: return "arrow.up.doc.on.clipboard"
            case .storage: return "chart.pie"
            }
        }
    }

    @State private var selection: Feature? = .backup

    private var current: Feature { selection ?? .backup }
    @State private var isShowingSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Feature.allCases) { feature in
                    Label(feature.title, systemImage: feature.symbolName)
                        .tag(feature)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                switch current {
                case .backup:
                    BackupView(onOpenSettings: { isShowingSettings = true })
                case .storage:
                    StorageScanView()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(auth)
                .environmentObject(coordinator)
        }
    }

    private var header: some View {
        HStack {
            Label(current.title, systemImage: current.symbolName)
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
