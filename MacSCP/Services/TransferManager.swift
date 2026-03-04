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
        Task.detached { [weak self] in
            do {
                let process: Process
                if task.direction == .upload {
                    process = await service.upload(localPath: task.localPath, remotePath: task.remotePath)
                } else {
                    process = await service.download(remotePath: task.remotePath, localPath: task.localPath)
                }

                await MainActor.run { task.process = process }

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
                    if process.terminationStatus == 0 {
                        task.markCompleted()
                    } else {
                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                        task.markFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    self?.activeTransfers = max(0, (self?.activeTransfers ?? 1) - 1)
                    self?.processQueue()
                }
            } catch {
                await MainActor.run {
                    task.markFailed(error.localizedDescription)
                    self?.activeTransfers = max(0, (self?.activeTransfers ?? 1) - 1)
                    self?.processQueue()
                }
            }
        }
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
