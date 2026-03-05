import SwiftUI

struct TransferQueueView: View {
    @EnvironmentObject var transferManager: TransferManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .foregroundColor(.accentColor)
                Text("Transfers")
                    .font(.headline)

                if transferManager.activeTransfers > 0 {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("\(transferManager.activeTransfers) active")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)
                }

                Spacer()

                if !transferManager.tasks.isEmpty {
                    Button(action: { transferManager.clearCompleted() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption)
                            Text("Clear Done")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)

                    Button(action: { transferManager.cancelAll() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                            Text("Cancel All")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if transferManager.tasks.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Drag files between panes or use the transfer buttons")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(transferManager.tasks) { task in
                            TransferRowView(task: task) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    transferManager.cancelTask(task)
                                }
                            }
                            Divider().padding(.leading, 44)
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
            // Direction icon with color
            ZStack {
                Circle()
                    .fill(directionColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: task.directionIcon)
                    .font(.system(size: 14))
                    .foregroundColor(directionColor)
            }

            // File info and progress
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.fileName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    statusBadge
                }

                if task.status == .inProgress {
                    // Custom colored progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: task.direction == .upload
                                            ? [.blue.opacity(0.8), .blue]
                                            : [.green.opacity(0.8), .green],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * task.progress), height: 6)
                                .animation(.easeInOut(duration: 0.3), value: task.progress)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(task.formattedTransferred)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)

                        if task.progressPercent > 0 {
                            Text("\(task.progressPercent)%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(directionColor)
                        }

                        Spacer()

                        if task.speed > 0 {
                            Image(systemName: "speedometer")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(task.formattedSpeed)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        if task.totalBytes > 0 {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(task.eta)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if task.status == .queued {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text("Waiting in queue...")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                if let error = task.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(error)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundColor(.red)
                }

                if task.status == .completed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text("Transfer complete")
                            .font(.caption2)
                    }
                    .foregroundColor(.green)
                }
            }

            // Cancel/retry button
            if task.status == .inProgress || task.status == .queued {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Cancel transfer")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground)
        .animation(.easeInOut(duration: 0.2), value: task.status)
    }

    private var directionColor: Color {
        task.direction == .upload ? .blue : .green
    }

    private var rowBackground: Color {
        switch task.status {
        case .inProgress: return directionColor.opacity(0.03)
        case .completed: return Color.green.opacity(0.03)
        case .failed: return Color.red.opacity(0.03)
        default: return Color.clear
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: task.statusIcon)
                .font(.system(size: 9))

            Text(task.status.rawValue)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1))
        .cornerRadius(4)
    }

    private var statusColor: Color {
        switch task.status {
        case .queued: return .secondary
        case .inProgress: return directionColor
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}
