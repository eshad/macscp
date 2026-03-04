import Foundation

actor SSHService {
    private let connection: ServerConnection
    private var password: String?

    init(connection: ServerConnection, password: String? = nil) {
        self.connection = connection
        self.password = password
    }

    /// Test SSH connectivity
    func testConnection() async throws -> Bool {
        let result = try await runSSH(command: "echo connected", timeout: 10)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "connected"
    }

    /// Execute a remote command via SSH
    func execute(_ command: String, timeout: TimeInterval = 30) async throws -> String {
        try await runSSH(command: command, timeout: timeout)
    }

    /// Build common SSH arguments
    private func sshBaseArgs() -> [String] {
        var args = [String]()
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
        args.append(contentsOf: ["-o", "ConnectTimeout=10"])
        args.append(contentsOf: ["-o", "BatchMode=\(password == nil ? "yes" : "no")"])
        args.append(contentsOf: connection.sshPortArgs)

        if let keyPath = connection.sshKeyPath, !keyPath.isEmpty {
            args.append(contentsOf: ["-i", keyPath])
        }

        return args
    }

    private func runSSH(command: String, timeout: TimeInterval) async throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = sshBaseArgs()
        args.append(connection.sshTarget)
        args.append(command)
        process.arguments = args

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        configurePasswordAuth(process: process)

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            let workItem = DispatchWorkItem {
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let errorMsg = stderr.isEmpty ? "SSH command failed with exit code \(process.terminationStatus)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: SSHError.commandFailed(errorMsg))
                }
            }

            DispatchQueue.global().async(execute: workItem)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                    continuation.resume(throwing: SSHError.timeout)
                }
            }
        }
    }

    /// Set up SSH_ASKPASS for password authentication
    private func configurePasswordAuth(process: Process) {
        guard let password = password, connection.authMethod == .password else { return }

        let askpassScript = createAskpassScript(password: password)
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpassScript
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = ":0"
        process.environment = env
    }

    /// Create a temporary askpass script that echoes the password
    private func createAskpassScript(password: String) -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("macscp_askpass_\(UUID().uuidString).sh")

        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")

        let script = """
        #!/bin/bash
        echo '\(escaped)'
        """

        try? script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptPath.path
        )

        // Clean up after a delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(at: scriptPath)
        }

        return scriptPath.path
    }
}

enum SSHError: LocalizedError {
    case commandFailed(String)
    case timeout
    case connectionFailed(String)
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .timeout: return "Connection timed out"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed: return "Authentication failed"
        }
    }
}
