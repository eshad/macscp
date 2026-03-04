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
