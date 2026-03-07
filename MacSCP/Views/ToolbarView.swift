import SwiftUI

struct ToolbarView: View {
    let tabCount: Int
    let selectedTabName: String?
    var onConnect: () -> Void
    var onDisconnect: () -> Void
    var onRefresh: () -> Void
    var onAbout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("MacSCP")
                .font(.title3.bold())

            Divider()
                .frame(height: 20)

            // Connection status
            if let name = selectedTabName {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.body)
                        .foregroundColor(.primary)
                    if tabCount > 1 {
                        Text("(\(tabCount) connections)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Disconnected")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (Cmd+R)")

            if tabCount > 0 {
                Button(action: onDisconnect) {
                    Label("Disconnect", systemImage: "bolt.horizontal.circle")
                }
                .help("Disconnect active tab")
            }

            Button(action: onConnect) {
                Label("Connect", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .help("Connect to Server")

            Divider()
                .frame(height: 20)

            Button(action: onAbout) {
                Label("About", systemImage: "info.circle")
            }
            .help("About MacSCP")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
