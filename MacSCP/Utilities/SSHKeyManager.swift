import Foundation

struct SSHKeyManager {
    static let sshDirectory = NSHomeDirectory() + "/.ssh"

    /// Discover available SSH keys
    static func discoverKeys() -> [SSHKeyInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sshDirectory) else {
            return []
        }

        var keys: [SSHKeyInfo] = []
        let privateKeyNames = files.filter { name in
            // Common private key names
            let knownNames = ["id_rsa", "id_ed25519", "id_ecdsa", "id_dsa"]
            if knownNames.contains(name) { return true }
            // Files without .pub extension that have a .pub counterpart
            if !name.hasSuffix(".pub") && files.contains(name + ".pub") { return true }
            return false
        }

        for name in privateKeyNames {
            let path = sshDirectory + "/" + name
            let pubPath = path + ".pub"
            let hasPublicKey = fm.fileExists(atPath: pubPath)

            keys.append(SSHKeyInfo(
                name: name,
                path: path,
                publicKeyPath: hasPublicKey ? pubPath : nil,
                type: detectKeyType(name: name)
            ))
        }

        return keys.sorted { $0.name < $1.name }
    }

    /// Check if ssh-agent has any loaded keys
    static func agentHasKeys() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-add")
        process.arguments = ["-l"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return process.terminationStatus == 0 && !output.contains("no identities")
        } catch {
            return false
        }
    }

    private static func detectKeyType(name: String) -> String {
        if name.contains("ed25519") { return "Ed25519" }
        if name.contains("ecdsa") { return "ECDSA" }
        if name.contains("rsa") { return "RSA" }
        if name.contains("dsa") { return "DSA" }
        return "Unknown"
    }
}

struct SSHKeyInfo: Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let publicKeyPath: String?
    let type: String
}

// MARK: - SSH Config Parser

struct SSHConfigHost: Identifiable {
    var id: String { alias }
    let alias: String
    let hostname: String
    let user: String
    let port: Int
    let identityFile: String?

    var displayName: String {
        if alias != hostname && !alias.isEmpty {
            return alias
        }
        if !user.isEmpty {
            return "\(user)@\(hostname)"
        }
        return hostname
    }

    func toServerConnection() -> ServerConnection {
        ServerConnection(
            name: alias,
            host: hostname,
            port: port,
            username: user,
            authMethod: identityFile != nil ? .sshKey : .sshKey,
            sshKeyPath: identityFile
        )
    }
}

struct SSHConfigParser {
    static func parse() -> [SSHConfigHost] {
        let configPath = SSHKeyManager.sshDirectory + "/config"
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return []
        }

        var hosts: [SSHConfigHost] = []
        var currentAlias: String?
        var currentHostname: String?
        var currentUser: String?
        var currentPort: Int?
        var currentIdentityFile: String?

        func flushHost() {
            guard let alias = currentAlias,
                  alias != "*" else { return }

            let hostname = currentHostname ?? alias
            let user = currentUser ?? ""
            let port = currentPort ?? 22

            // Expand ~ in identity file path
            var keyPath = currentIdentityFile
            if let kp = keyPath, kp.hasPrefix("~") {
                keyPath = NSHomeDirectory() + String(kp.dropFirst())
            }

            hosts.append(SSHConfigHost(
                alias: alias,
                hostname: hostname,
                user: user,
                port: port,
                identityFile: keyPath
            ))

            currentAlias = nil
            currentHostname = nil
            currentUser = nil
            currentPort = nil
            currentIdentityFile = nil
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "host":
                flushHost()
                // Skip wildcard patterns
                if !value.contains("*") && !value.contains("?") {
                    currentAlias = value
                }
            case "hostname":
                currentHostname = value
            case "user":
                currentUser = value
            case "port":
                currentPort = Int(value)
            case "identityfile":
                currentIdentityFile = value
            default:
                break
            }
        }

        flushHost()
        return hosts
    }
}
