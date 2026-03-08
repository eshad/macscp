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
        args.append(contentsOf: connection.sshIdentityArgs)

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

        do {
            try process.run()
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }

        // Use an actor-isolated flag to prevent double-resume
        let guard_ = ContinuationGuard()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                guard guard_.tryResume() else { return }

                // Filter out SSH warning lines (e.g. post-quantum warnings)
                let filteredStderr = stderr
                    .components(separatedBy: "\n")
                    .filter { line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        return !trimmed.hasPrefix("**") && !trimmed.isEmpty
                    }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let errorMsg = filteredStderr.isEmpty
                        ? "SSH command failed with exit code \(process.terminationStatus)"
                        : filteredStderr
                    continuation.resume(throwing: SSHError.commandFailed(errorMsg))
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
                guard guard_.tryResume() else { return }
                continuation.resume(throwing: SSHError.timeout)
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

/// Thread-safe guard to ensure a continuation is only resumed once
final class ContinuationGuard: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    /// Returns true if this is the first call (safe to resume). Returns false if already resumed.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
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
