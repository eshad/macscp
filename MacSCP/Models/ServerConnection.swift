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
    var isSaved: Bool
    var lastConnected: Date?

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: AuthMethod = .sshKey,
        identityFilePath: String? = nil,
        isSaved: Bool = false,
        lastConnected: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.identityFilePath = identityFilePath
        self.isSaved = isSaved
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
        return ["-o", "IdentitiesOnly=yes", "-i", path]
    }
}

class ConnectionManager: ObservableObject {
    @Published var allConnections: [ServerConnection] = []

    private let storageKey = "SavedConnections"

    var savedConnections: [ServerConnection] {
        allConnections.filter { $0.isSaved }
    }

    var historyConnections: [ServerConnection] {
        allConnections.filter { !$0.isSaved }
            .sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
    }

    init() {
        loadConnections()
    }

    /// Add to history when connecting (auto-save)
    func addToHistory(_ connection: ServerConnection) {
        var conn = connection
        conn.lastConnected = Date()
        // Update existing entry with same host+user, or add new
        if let index = allConnections.firstIndex(where: { $0.id == conn.id }) {
            conn.isSaved = allConnections[index].isSaved
            allConnections[index] = conn
        } else if let index = allConnections.firstIndex(where: { !$0.isSaved && $0.host == conn.host && $0.username == conn.username }) {
            conn.id = allConnections[index].id
            allConnections[index] = conn
        } else {
            conn.isSaved = false
            allConnections.append(conn)
        }
        persistConnections()
    }

    /// Explicitly save a connection (bookmark it)
    func saveConnection(_ connection: ServerConnection) {
        var conn = connection
        conn.isSaved = true
        if let index = allConnections.firstIndex(where: { $0.id == conn.id }) {
            allConnections[index] = conn
        } else {
            allConnections.append(conn)
        }
        persistConnections()
    }

    /// Remove saved status (move back to history)
    func unsaveConnection(_ connection: ServerConnection) {
        if let index = allConnections.firstIndex(where: { $0.id == connection.id }) {
            allConnections[index].isSaved = false
            persistConnections()
        }
    }

    func deleteConnection(_ connection: ServerConnection) {
        allConnections.removeAll { $0.id == connection.id }
        persistConnections()
    }

    private func persistConnections() {
        if let data = try? JSONEncoder().encode(allConnections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let connections = try? JSONDecoder().decode([ServerConnection].self, from: data) else {
            return
        }
        allConnections = connections
    }
}
