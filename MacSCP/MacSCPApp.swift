import SwiftUI

@main
struct MacSCPApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var transferManager = TransferManager()
    @StateObject private var tabManager = RemoteTabManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(connectionManager)
                .environmentObject(transferManager)
                .environmentObject(tabManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
