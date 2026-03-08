import Foundation
import SwiftUI

struct RemoteTab: Identifiable {
    let id: UUID
    var connection: ServerConnection
    var password: String?
    var sftpService: SFTPService?
    var remotePath: String = "~"
    var homePath: String = "~"
    var remoteFiles: [FileItem] = []
    var isLoadingRemote: Bool = false
    var isConnected: Bool = false

    init(connection: ServerConnection, password: String?) {
        self.id = UUID()
        self.connection = connection
        self.password = password
    }
}

@MainActor
class RemoteTabManager: ObservableObject {
    @Published var tabs: [RemoteTab] = []
    @Published var selectedTabId: UUID?

    var selectedTab: RemoteTab? {
        guard let id = selectedTabId else { return nil }
        return tabs.first { $0.id == id }
    }

    var selectedTabIndex: Int? {
        guard let id = selectedTabId else { return nil }
        return tabs.firstIndex { $0.id == id }
    }

    var hasAnyConnection: Bool {
        !tabs.isEmpty
    }

    func addTab(connection: ServerConnection, password: String?) -> UUID {
        let tab = RemoteTab(connection: connection, password: password)
        tabs.append(tab)
        selectedTabId = tab.id
        return tab.id
    }

    func closeTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if selectedTabId == id {
            selectedTabId = tabs.last?.id
        }
    }

    func updateTab(_ id: UUID, _ update: (inout RemoteTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        update(&tabs[index])
    }
}
