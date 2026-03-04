import SwiftUI

struct TransferQueueView: View {
    @EnvironmentObject var transferManager: TransferManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .foregroundColor(.accentColor)
                Text("Transfer Queue")
                    .font(.headline)

                if transferManager.activeTransfers > 0 {
                    Text("(\(transferManager.activeTransfers) active)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !transferManager.tasks.isEmpty {
                    Button("Clear Done") {
                        transferManager.clearCompleted()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("Cancel All") {
                        transferManager.cancelAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if transferManager.tasks.isEmpty {
                VStack {
                    Spacer()
                    Text("No transfers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(transferManager.tasks) { task in
                            TransferRowView(task: task) {
                                transferManager.cancelTask(task)
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct TransferRowView: View {
    @ObservedObject var task: TransferTask
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Direction icon
            Image(systemName: task.directionIcon)
                .font(.system(size: 16))
                .foregroundColor(task.direction == .upload ? .blue : .green)

            // File info and progress
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.fileName)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()

                    statusBadge
                }

                if task.status == .inProgress {
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(task.formattedTransferred)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(task.formattedSpeed)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("ETA: \(task.eta)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = task.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            // Cancel button
            if task.status == .inProgress || task.status == .queued {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: task.statusIcon)
                .font(.caption)

            Text(task.status.rawValue)
                .font(.caption)
        }
        .foregroundColor(statusColor)
    }

    private var statusColor: Color {
        switch task.status {
        case .queued: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}
