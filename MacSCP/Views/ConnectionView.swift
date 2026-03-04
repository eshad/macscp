import SwiftUI

enum SidebarTab: String, CaseIterable {
    case sshConfig = "SSH Config"
    case saved = "Saved"
}

struct ConnectionView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var connection = ServerConnection()
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var selectedSaved: ServerConnection?
    @State private var sidebarTab: SidebarTab = .sshConfig
    @State private var sshConfigHosts: [SSHConfigHost] = []
    @State private var configSearchText = ""

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
                // Sidebar with tabs
                sidebarView
                    .frame(width: 220)

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

                if isTesting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

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
        .frame(width: 720, height: 520)
        .onAppear {
            sshConfigHosts = SSHConfigParser.parse()
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch sidebarTab {
            case .sshConfig:
                sshConfigList
            case .saved:
                savedConnectionsList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - SSH Config Hosts

    private var sshConfigList: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter hosts...", text: $configSearchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !configSearchText.isEmpty {
                    Button(action: { configSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            if filteredConfigHosts.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No SSH hosts found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("~/.ssh/config")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredConfigHosts) { host in
                            sshConfigRow(host)
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(sshConfigHosts.count) hosts from ~/.ssh/config")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private func sshConfigRow(_ host: SSHConfigHost) -> some View {
        HStack(spacing: 8) {
            Image(systemName: host.identityFile != nil ? "key.fill" : "terminal.fill")
                .font(.system(size: 12))
                .foregroundColor(host.identityFile != nil ? .orange : .blue)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(host.alias)
                    .font(.body.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !host.user.isEmpty {
                        Text(host.user)
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if host.alias != host.hostname {
                        Text(host.hostname)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if host.port != 22 {
                        Text(":\(host.port)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            connection.host == host.hostname && connection.username == host.user
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .cornerRadius(4)
        .onTapGesture {
            selectSSHConfigHost(host)
        }
        .onTapGesture(count: 2) {
            selectSSHConfigHost(host)
            // Quick connect on double-click
            let pwd: String? = nil
            connectionManager.saveConnection(connection)
            dismiss()
            onConnect(connection, pwd)
        }
    }

    private func selectSSHConfigHost(_ host: SSHConfigHost) {
        connection = host.toServerConnection()
        testResult = nil
    }

    private var filteredConfigHosts: [SSHConfigHost] {
        if configSearchText.isEmpty { return sshConfigHosts }
        let query = configSearchText.lowercased()
        return sshConfigHosts.filter {
            $0.alias.lowercased().contains(query) ||
            $0.hostname.lowercased().contains(query) ||
            $0.user.lowercased().contains(query)
        }
    }

    // MARK: - Saved Connections

    private var savedConnectionsList: some View {
        VStack(spacing: 0) {
            if connectionManager.savedConnections.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No saved connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Connect to save")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(connectionManager.savedConnections) { saved in
                            HStack(spacing: 8) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 12))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(saved.displayName)
                                        .font(.body.bold())
                                        .lineLimit(1)
                                    Text("\(saved.host):\(saved.port)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(
                                selectedSaved?.id == saved.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(4)
                            .onTapGesture {
                                connection = saved
                                selectedSaved = saved
                                testResult = nil
                            }
                            .onTapGesture(count: 2) {
                                connection = saved
                                let pwd: String? = nil
                                connectionManager.saveConnection(connection)
                                dismiss()
                                onConnect(connection, pwd)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    connectionManager.deleteConnection(saved)
                                }
                            }

                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Connection Form

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

    // MARK: - Actions

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
