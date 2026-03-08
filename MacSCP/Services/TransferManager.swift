import Foundation
import SwiftUI

@MainActor
class TransferManager: ObservableObject {
    @Published var tasks: [TransferTask] = []
    @Published var activeTransfers = 0

    private let maxConcurrent = 3

    /// Called when a transfer completes (direction, success, tabId)
    var onTransferCompleted: ((TransferDirection, Bool, UUID?) -> Void)?

    func uploadFile(localPath: String, remotePath: String, fileName: String, connection: ServerConnection, password: String?, tabId: UUID?) {
        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0

        let task = TransferTask(
            direction: .upload,
            localPath: localPath,
            remotePath: remotePath,
            fileName: fileName,
            totalBytes: fileSize,
            connection: connection,
            password: password,
            tabId: tabId
        )

        tasks.insert(task, at: 0)
        processQueue()
    }

    func downloadFile(remotePath: String, localPath: String, fileName: String, remoteSize: Int64, connection: ServerConnection, password: String?, tabId: UUID?) {
        let task = TransferTask(
            direction: .download,
            localPath: localPath,
            remotePath: remotePath,
            fileName: fileName,
            totalBytes: remoteSize,
            connection: connection,
            password: password,
            tabId: tabId
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
        let queued = tasks.filter { $0.status == .queued }
        let available = maxConcurrent - activeTransfers

        for task in queued.prefix(available) {
            activeTransfers += 1
            task.markStarted()
            startTransfer(task: task)
        }
    }

    private func startTransfer(task: TransferTask) {
        let connection = task.connection

        // Validate paths
        guard !task.localPath.isEmpty, !task.remotePath.isEmpty else {
            task.markFailed("Invalid file path")
            activeTransfers = max(0, activeTransfers - 1)
            return
        }

        // Capture all values as simple types for the background thread
        let localPath = task.localPath
        let remotePath = task.remotePath
        let direction = task.direction
        let sshTarget = connection.sshTarget
        let scpPortArgs = connection.scpPortArgs
        let sshIdentityArgs = connection.sshIdentityArgs
        let escapedRemotePath = scpEscapeRemotePath(remotePath)
        let tmpDir = NSTemporaryDirectory()
        let tabId = task.tabId

        // Everything happens on the background queue - no crossing threads
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            process.currentDirectoryURL = URL(fileURLWithPath: tmpDir)

            var args = ["-r"]
            args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
            args.append(contentsOf: scpPortArgs)
            args.append(contentsOf: sshIdentityArgs)

            if direction == .upload {
                args.append(localPath)
                args.append("\(sshTarget):\(escapedRemotePath)")
            } else {
                args.append("\(sshTarget):\(escapedRemotePath)")
                args.append(localPath)
            }

            process.arguments = args

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = FileHandle.nullDevice

            DispatchQueue.main.async { task.process = process }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    task.markFailed(error.localizedDescription)
                    self?.activeTransfers = max(0, (self?.activeTransfers ?? 1) - 1)
                    self?.onTransferCompleted?(direction, false, tabId)
                    self?.processQueue()
                }
                return
            }

            // Monitor progress for downloads
            var progressTimer: Timer?
            if direction == .download {
                let monitorPath = localPath
                DispatchQueue.main.async {
                    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: monitorPath)[.size] as? Int64) ?? 0
                        task.updateProgress(bytes: fileSize)
                    }
                }
            }

            process.waitUntilExit()

            DispatchQueue.main.async {
                progressTimer?.invalidate()

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
                self?.onTransferCompleted?(direction, success, tabId)
                self?.processQueue()
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
}
