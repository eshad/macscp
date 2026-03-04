import SwiftUI

struct ConnectionManagerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Connections")
                .font(.title2.bold())

            if connectionManager.savedConnections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No saved connections")
                        .foregroundColor(.secondary)
                    Text("Connections will appear here after you connect to a server.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(connectionManager.savedConnections) { connection in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(connection.displayName)
                                    .font(.body.bold())
                                Text("\(connection.username)@\(connection.host):\(connection.port)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let date = connection.lastConnected {
                                    Text("Last connected: \(date.formatted())")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Image(systemName: connection.authMethod == .sshKey ? "key.fill" : "lock.fill")
                                    .foregroundColor(.secondary)
                                    .help(connection.authMethod.rawValue)

                                Button(role: .destructive) {
                                    connectionManager.deleteConnection(connection)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}
