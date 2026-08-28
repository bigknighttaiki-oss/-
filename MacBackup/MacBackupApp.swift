import SwiftUI

@main
struct MacBackupApp: App {
    @StateObject private var auth: DropboxAuthService
    @StateObject private var coordinator: BackupCoordinator

    @MainActor
    init() {
        let auth = DropboxAuthService()
        _auth = StateObject(wrappedValue: auth)
        _coordinator = StateObject(wrappedValue: BackupCoordinator(auth: auth))
    }

    var body: some Scene {
        WindowGroup("Mac Backup") {
            ContentView()
                .environmentObject(auth)
                .environmentObject(coordinator)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
