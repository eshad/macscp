import Foundation

actor SFTPService {
    private let ssh: SSHService
    private let connection: ServerConnection

    init(connection: ServerConnection, password: String? = nil) {
        self.connection = connection
        self.ssh = SSHService(connection: connection, password: password)
    }

    /// Test connectivity
    func testConnection() async throws -> Bool {
        try await ssh.testConnection()
    }

    /// List files in a remote directory
    func listFiles(at path: String) async throws -> [FileItem] {
        // Use stat-style output for reliable parsing
        let command = "ls -la --time-style=long-iso \(escapePath(path)) 2>/dev/null || ls -la \(escapePath(path))"
        let output = try await ssh.execute(command, timeout: 15)
        return parseDirectoryListing(output, parentPath: path)
    }

    /// Create a directory
    func createDirectory(at path: String) async throws {
        _ = try await ssh.execute("mkdir -p \(escapePath(path))")
    }

    /// Delete a file or directory
    func delete(at path: String, isDirectory: Bool) async throws {
        let flag = isDirectory ? "-rf" : "-f"
        _ = try await ssh.execute("rm \(flag) \(escapePath(path))")
    }

    /// Rename/move a file
    func rename(from oldPath: String, to newPath: String) async throws {
        _ = try await ssh.execute("mv \(escapePath(oldPath)) \(escapePath(newPath))")
    }

    /// Change permissions
    func chmod(_ permissions: String, at path: String) async throws {
        _ = try await ssh.execute("chmod \(permissions) \(escapePath(path))")
    }

    /// Get file size (for progress tracking)
    func fileSize(at path: String) async throws -> Int64 {
        let output = try await ssh.execute("stat -f%z \(escapePath(path)) 2>/dev/null || stat -c%s \(escapePath(path)) 2>/dev/null || wc -c < \(escapePath(path))")
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int64(cleaned) ?? 0
    }

    /// List directory names in a path (for autocomplete suggestions)
    func listDirectoryNames(at path: String) async throws -> [String] {
        let command = "ls -1F \(escapePath(path)) 2>/dev/null | grep '/$' | sed 's/\\/$//' | head -20"
        let output = try await ssh.execute(command, timeout: 10)
        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix(".") }
    }

    /// Get remote home directory
    func homeDirectory() async throws -> String {
        let output = try await ssh.execute("echo $HOME")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Escape remote path for scp (remote shell interprets this)
    private func scpEscapeRemotePath(_ path: String) -> String {
        // scp remote paths are interpreted by the remote shell,
        // so we need to escape spaces and special chars
        var escaped = path
        for char in [" ", "'", "\"", "(", ")", "&", ";", "|", "$", "`", "!", "#", "*", "?", "{", "}", "[", "]"] {
            escaped = escaped.replacingOccurrences(of: char, with: "\\\(char)")
        }
        return escaped
    }

    /// Download a file using scp
    func download(remotePath: String, localPath: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")

        var args = ["-r"]
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
        args.append(contentsOf: connection.scpPortArgs)

        if let keyPath = connection.sshKeyPath, !keyPath.isEmpty {
            args.append(contentsOf: ["-i", keyPath])
        }

        args.append("\(connection.sshTarget):\(scpEscapeRemotePath(remotePath))")
        args.append(localPath)

        process.arguments = args
        return process
    }

    /// Upload a file using scp
    func upload(localPath: String, remotePath: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")

        var args = ["-r"]
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
        args.append(contentsOf: connection.scpPortArgs)

        if let keyPath = connection.sshKeyPath, !keyPath.isEmpty {
            args.append(contentsOf: ["-i", keyPath])
        }

        args.append(localPath)
        args.append("\(connection.sshTarget):\(scpEscapeRemotePath(remotePath))")

        process.arguments = args
        return process
    }

    // MARK: - Parsing

    private func parseDirectoryListing(_ output: String, parentPath: String) -> [FileItem] {
        var items = [FileItem]()
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("total"),
                  trimmed.count > 10 else { continue }

            if let item = parseLsLine(trimmed, parentPath: parentPath) {
                if item.name != "." && item.name != ".." {
                    items.append(item)
                }
            }
        }

        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func parseLsLine(_ line: String, parentPath: String) -> FileItem? {
        // Parse: drwxr-xr-x  2 user group  4096 2024-01-15 10:30 filename
        // or:    drwxr-xr-x  2 user group  4096 Jan 15 10:30 filename
        let components = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
        guard components.count >= 9 else {
            // Try with fewer splits for different ls formats
            return parseLsLineFallback(line, parentPath: parentPath)
        }

        let perms = String(components[0])
        let owner = String(components[2])
        let group = String(components[3])
        let size = Int64(components[4]) ?? 0
        let name: String

        // Check if it's long-iso format (2024-01-15 10:30) or traditional (Jan 15 10:30)
        let dateStr: String
        if components[5].contains("-") {
            // long-iso: date time filename
            dateStr = "\(components[5]) \(components[6])"
            name = components.dropFirst(7).joined(separator: " ")
        } else {
            // traditional: month day time/year filename
            dateStr = "\(components[5]) \(components[6]) \(components[7])"
            name = components.dropFirst(8).joined(separator: " ")
        }

        guard !name.isEmpty else { return nil }

        // Handle symlinks: name -> target
        let displayName: String
        let isSymlink = perms.hasPrefix("l")
        if isSymlink, let arrowRange = name.range(of: " -> ") {
            displayName = String(name[name.startIndex..<arrowRange.lowerBound])
        } else {
            displayName = name
        }

        let isDirectory = perms.hasPrefix("d")
        let date = parseDate(dateStr)

        return FileItem(
            name: displayName,
            path: parentPath,
            size: size,
            modificationDate: date,
            permissions: perms,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            owner: owner,
            group: group
        )
    }

    private func parseLsLineFallback(_ line: String, parentPath: String) -> FileItem? {
        let components = line.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 8 else { return nil }

        let perms = String(components[0])
        let owner = String(components[2])
        let group = String(components[3])
        let size = Int64(components[4]) ?? 0
        let name = components.dropFirst(7).joined(separator: " ")

        guard !name.isEmpty else { return nil }

        let displayName: String
        let isSymlink = perms.hasPrefix("l")
        if isSymlink, let arrowRange = name.range(of: " -> ") {
            displayName = String(name[name.startIndex..<arrowRange.lowerBound])
        } else {
            displayName = name
        }

        return FileItem(
            name: displayName,
            path: parentPath,
            size: size,
            modificationDate: nil,
            permissions: perms,
            isDirectory: perms.hasPrefix("d"),
            isSymlink: isSymlink,
            owner: owner,
            group: group
        )
    }

    private func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = {
            let f1 = DateFormatter()
            f1.dateFormat = "yyyy-MM-dd HH:mm"
            f1.locale = Locale(identifier: "en_US_POSIX")

            let f2 = DateFormatter()
            f2.dateFormat = "MMM dd HH:mm"
            f2.locale = Locale(identifier: "en_US_POSIX")

            let f3 = DateFormatter()
            f3.dateFormat = "MMM dd yyyy"
            f3.locale = Locale(identifier: "en_US_POSIX")

            return [f1, f2, f3]
        }()

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    private func escapePath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
