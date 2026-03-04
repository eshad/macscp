import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var connection = ServerConnection()
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var selectedSaved: ServerConnection?

    var onConnect: (ServerConnection, String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Connect to Server")
                    .font(.title2.bold())
                Spacer()
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                // Saved connections sidebar
                savedConnectionsList
                    .frame(width: 200)

                Divider()

                // Connection form
                connectionForm
                    .frame(minWidth: 350)
            }

            Divider()

            // Bottom buttons
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(connection.host.isEmpty || connection.username.isEmpty || isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("Success") ? .green : .red)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect") {
                    let pwd = connection.authMethod == .password ? password : nil
                    connectionManager.saveConnection(connection)
                    dismiss()
                    onConnect(connection, pwd)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(connection.host.isEmpty || connection.username.isEmpty)
            }
            .padding()
        }
        .frame(width: 650, height: 450)
    }

    private var savedConnectionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saved")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if connectionManager.savedConnections.isEmpty {
                VStack {
                    Spacer()
                    Text("No saved connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(connectionManager.savedConnections, selection: $selectedSaved) { saved in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.displayName)
                            .font(.body.bold())
                        Text("\(saved.host):\(saved.port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        connection = saved
                        selectedSaved = saved
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            connectionManager.deleteConnection(saved)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var connectionForm: some View {
        Form {
            Section("Server") {
                TextField("Connection Name", text: $connection.name)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    TextField("Host", text: $connection.host)
                        .textFieldStyle(.roundedBorder)

                    TextField("Port", value: $connection.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }

                TextField("Username", text: $connection.username)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Authentication") {
                Picker("Method", selection: $connection.authMethod) {
                    ForEach(AuthMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if connection.authMethod == .sshKey {
                    HStack {
                        TextField("SSH Key Path", text: Binding(
                            get: { connection.sshKeyPath ?? "" },
                            set: { connection.sshKeyPath = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button("Browse") {
                            browseSSHKey()
                        }
                    }

                    Text("Leave empty to use ssh-agent default keys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let conn = connection
        let pwd = connection.authMethod == .password ? password : nil

        Task {
            let service = SFTPService(connection: conn, password: pwd)
            do {
                let ok = try await service.testConnection()
                await MainActor.run {
                    testResult = ok ? "Success!" : "Failed"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    private func browseSSHKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.prompt = "Select SSH Key"

        if panel.runModal() == .OK, let url = panel.url {
            connection.sshKeyPath = url.path
        }
    }
}
