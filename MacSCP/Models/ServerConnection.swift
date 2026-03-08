import Foundation

enum AuthMethod: String, Codable, CaseIterable {
    case sshKey = "SSH Key"
    case password = "Password"
}

struct ServerConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var identityFilePath: String?
    var lastConnected: Date?

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: AuthMethod = .sshKey,
        identityFilePath: String? = nil,
        lastConnected: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.identityFilePath = identityFilePath
        self.lastConnected = lastConnected
    }

    var displayName: String {
        if !name.isEmpty { return name }
        return "\(username)@\(host)"
    }

    var sshTarget: String {
        // If host already contains user@, use it directly
        if host.contains("@") {
            return host
        }
        return "\(username)@\(host)"
    }

    var sshPortArgs: [String] {
        port == 22 ? [] : ["-p", "\(port)"]
    }

    var scpPortArgs: [String] {
        port == 22 ? [] : ["-P", "\(port)"]
    }

    var sshIdentityArgs: [String] {
        guard let path = identityFilePath, !path.isEmpty else { return [] }
        return ["-i", path]
    }
}

class ConnectionManager: ObservableObject {
    @Published var savedConnections: [ServerConnection] = []

    private let storageKey = "SavedConnections"

    init() {
        loadConnections()
    }

    func saveConnection(_ connection: ServerConnection) {
        var conn = connection
        conn.lastConnected = Date()
        if let index = savedConnections.firstIndex(where: { $0.id == conn.id }) {
            savedConnections[index] = conn
        } else {
            savedConnections.append(conn)
        }
        persistConnections()
    }

    func deleteConnection(_ connection: ServerConnection) {
        savedConnections.removeAll { $0.id == connection.id }
        persistConnections()
    }

    private func persistConnections() {
        if let data = try? JSONEncoder().encode(savedConnections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let connections = try? JSONDecoder().decode([ServerConnection].self, from: data) else {
            return
        }
        savedConnections = connections
    }
}
