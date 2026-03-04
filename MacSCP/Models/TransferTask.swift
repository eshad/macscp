import Foundation

enum TransferDirection: String {
    case upload = "Upload"
    case download = "Download"
}

enum TransferStatus: String {
    case queued = "Queued"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

class TransferTask: Identifiable, ObservableObject {
    let id = UUID()
    let direction: TransferDirection
    let localPath: String
    let remotePath: String
    let fileName: String
    let totalBytes: Int64

    @Published var transferredBytes: Int64 = 0
    @Published var status: TransferStatus = .queued
    @Published var speed: Double = 0 // bytes per second
    @Published var errorMessage: String?

    var process: Process?
    private var startTime: Date?

    init(
        direction: TransferDirection,
        localPath: String,
        remotePath: String,
        fileName: String,
        totalBytes: Int64 = 0
    ) {
        self.direction = direction
        self.localPath = localPath
        self.remotePath = remotePath
        self.fileName = fileName
        self.totalBytes = totalBytes
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    var progressPercent: Int {
        Int(progress * 100)
    }

    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }

    var eta: String {
        guard speed > 0 else { return "--" }
        let remaining = Double(totalBytes - transferredBytes) / speed
        if remaining < 60 {
            return "\(Int(remaining))s"
        } else if remaining < 3600 {
            return "\(Int(remaining / 60))m \(Int(remaining.truncatingRemainder(dividingBy: 60)))s"
        }
        return "\(Int(remaining / 3600))h \(Int((remaining / 60).truncatingRemainder(dividingBy: 60)))m"
    }

    var formattedTransferred: String {
        let transferred = ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(transferred) / \(total)"
    }

    var statusIcon: String {
        switch status {
        case .queued: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    var directionIcon: String {
        direction == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    func markStarted() {
        status = .inProgress
        startTime = Date()
    }

    func updateProgress(bytes: Int64) {
        transferredBytes = bytes
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0 {
                speed = Double(transferredBytes) / elapsed
            }
        }
    }

    func markCompleted() {
        status = .completed
        transferredBytes = totalBytes
        speed = 0
    }

    func markFailed(_ message: String) {
        status = .failed
        errorMessage = message
        speed = 0
    }

    func cancel() {
        process?.terminate()
        status = .cancelled
        speed = 0
    }
}
