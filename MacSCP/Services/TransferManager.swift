import Foundation
import SwiftUI

@MainActor
class TransferManager: ObservableObject {
    @Published var tasks: [TransferTask] = []
    @Published var activeTransfers = 0

    private let maxConcurrent = 3
    private var sftpService: SFTPService?
    private var connection: ServerConnection?
    private var password: String?

    /// Called when a transfer completes (direction, success)
    var onTransferCompleted: ((TransferDirection, Bool) -> Void)?

    func configure(connection: ServerConnection, password: String?) {
        self.connection = connection
        self.password = password
        self.sftpService = SFTPService(connection: connection, password: password)
    }

    func uploadFile(localPath: String, remotePath: String, fileName: String) {
        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0

        let task = TransferTask(
            direction: .upload,
            localPath: localPath,
            remotePath: remotePath,
            fileName: fileName,
            totalBytes: fileSize
        )

        tasks.insert(task, at: 0)
        processQueue()
    }

    func downloadFile(remotePath: String, localPath: String, fileName: String, remoteSize: Int64) {
        let task = TransferTask(
            direction: .download,
            localPath: localPath,
            remotePath: remotePath,
            fileName: fileName,
            totalBytes: remoteSize
        )

        tasks.insert(task, at: 0)
        processQueue()
    }

    func cancelTask(_ task: TransferTask) {
        task.cancel()
        activeTransfers = max(0, activeTransfers - 1)
        processQueue()
    }

    func clearCompleted() {
        tasks.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }

    func cancelAll() {
        for task in tasks where task.status == .inProgress || task.status == .queued {
            task.cancel()
        }
        activeTransfers = 0
    }

    private func processQueue() {
        guard let sftpService = sftpService else { return }

        let queued = tasks.filter { $0.status == .queued }
        let available = maxConcurrent - activeTransfers

        for task in queued.prefix(available) {
            activeTransfers += 1
            task.markStarted()
            startTransfer(task: task, service: sftpService)
        }
    }

    private func startTransfer(task: TransferTask, service: SFTPService) {
        guard let connection = connection else {
            task.markFailed("No connection configured")
            activeTransfers = max(0, activeTransfers - 1)
            return
        }

        // Validate paths
        guard !task.localPath.isEmpty, !task.remotePath.isEmpty else {
            task.markFailed("Invalid file path")
            activeTransfers = max(0, activeTransfers - 1)
            return
        }

        // Build process directly here to avoid actor boundary issues
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

        var args = ["-r"]
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
        args.append(contentsOf: connection.scpPortArgs)

        if let keyPath = connection.sshKeyPath, !keyPath.isEmpty {
            args.append(contentsOf: ["-i", keyPath])
        }

        if task.direction == .upload {
            args.append(task.localPath)
            args.append("\(connection.sshTarget):\(scpEscapeRemotePath(task.remotePath))")
        } else {
            args.append("\(connection.sshTarget):\(scpEscapeRemotePath(task.remotePath))")
            args.append(task.localPath)
        }

        process.arguments = args
        task.process = process

        Task.detached { [weak self] in
            do {
                let stderrPipe = Pipe()
                process.standardError = stderrPipe
                process.standardOutput = FileHandle.nullDevice

                try process.run()

                // Monitor progress in background
                let monitorTask = Task.detached { [weak self] in
                    await self?.monitorProgress(task: task)
                }

                process.waitUntilExit()
                monitorTask.cancel()

                await MainActor.run {
                    let success: Bool
                    if process.terminationStatus == 0 {
                        task.markCompleted()
                        success = true
                    } else {
                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                        task.markFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                        success = false
                    }
                    self?.activeTransfers = max(0, (self?.activeTransfers ?? 1) - 1)
                    self?.onTransferCompleted?(task.direction, success)
                    self?.processQueue()
                }
            } catch {
                await MainActor.run {
                    task.markFailed(error.localizedDescription)
                    self?.activeTransfers = max(0, (self?.activeTransfers ?? 1) - 1)
                    self?.onTransferCompleted?(task.direction, false)
                    self?.processQueue()
                }
            }
        }
    }

    private func scpEscapeRemotePath(_ path: String) -> String {
        var escaped = path
        for char in [" ", "'", "\"", "(", ")", "&", ";", "|", "$", "`", "!", "#", "*", "?", "{", "}", "[", "]"] {
            escaped = escaped.replacingOccurrences(of: char, with: "\\\(char)")
        }
        return escaped
    }

    private func monitorProgress(task: TransferTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            let path: String
            if task.direction == .download {
                path = task.localPath
            } else {
                // For uploads, we can't easily track remote progress
                // Just show as indeterminate
                continue
            }

            let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0

            await MainActor.run {
                task.updateProgress(bytes: fileSize)
            }
        }
    }
}
