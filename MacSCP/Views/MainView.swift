import SwiftUI

struct MainView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var transferManager: TransferManager
    @EnvironmentObject var tabManager: RemoteTabManager
    @State private var showConnectionSheet = false
    @State private var localPath = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var localFiles: [FileItem] = []
    @State private var isLoadingLocal = false
    @State private var errorMessage: String?
    @State private var transferQueueHeight: CGFloat = 160
    @State private var selectedLocalItems: Set<UUID> = []
    @State private var selectedRemoteItems: Set<UUID> = []
    @State private var showEditor = false
    @State private var editorFileName = ""
    @State private var editorRemotePath = ""
    @State private var editorContent = ""
    @State private var editorConnection: ServerConnection?
    @State private var editorPassword: String?
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
            Divider()
            splitPanes
            Divider()
            TransferQueueView()
                .frame(height: transferQueueHeight)
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionView { connection, password in
                connect(to: connection, password: password)
            }
            .environmentObject(connectionManager)
        }
        .sheet(isPresented: $showEditor) {
            if let conn = editorConnection {
                RemoteTextEditorView(
                    fileName: editorFileName,
                    remotePath: editorRemotePath,
                    initialContent: editorContent,
                    connection: conn,
                    password: editorPassword,
                    isPresented: $showEditor
                )
                .frame(minWidth: 700, minHeight: 500)
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView(isPresented: $showAbout)
        }
        .onAppear {
            loadLocalFiles()
            transferManager.onTransferCompleted = { direction, success, tabId in
                guard success else { return }
                if direction == .upload {
                    if let tabId = tabId {
                        loadRemoteFiles(tabId: tabId)
                    }
                } else {
                    loadLocalFiles()
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        ToolbarView(
            tabCount: tabManager.tabs.count,
            selectedTabName: tabManager.selectedTab?.connection.displayName,
            onConnect: { showConnectionSheet = true },
            onDisconnect: disconnectActiveTab,
            onRefresh: refresh,
            onAbout: { showAbout = true }
        )
    }

    // MARK: - Split Panes

    private var splitPanes: some View {
        HSplitView {
            LocalFileBrowser(
                currentPath: $localPath,
                files: $localFiles,
                isLoading: $isLoadingLocal,
                onNavigate: { path in
                    localPath = path
                    loadLocalFiles()
                },
                onUpload: { items in
                    uploadFiles(items)
                }
            )
            .frame(minWidth: 300)

            // Transfer buttons between panes
            transferButtons

            // Right pane: tabbed remote browsers
            VStack(spacing: 0) {
                if !tabManager.tabs.isEmpty {
                    tabBar
                    Divider()
                }

                if let tab = tabManager.selectedTab {
                    RemoteFileBrowser(
                        currentPath: Binding(
                            get: { tab.remotePath },
                            set: { newPath in
                                tabManager.updateTab(tab.id) { $0.remotePath = newPath }
                            }
                        ),
                        files: Binding(
                            get: { tab.remoteFiles },
                            set: { newFiles in
                                tabManager.updateTab(tab.id) { $0.remoteFiles = newFiles }
                            }
                        ),
                        isLoading: Binding(
                            get: { tab.isLoadingRemote },
                            set: { val in
                                tabManager.updateTab(tab.id) { $0.isLoadingRemote = val }
                            }
                        ),
                        isConnected: tab.isConnected,
                        onNavigate: { path in
                            tabManager.updateTab(tab.id) { $0.remotePath = path }
                            loadRemoteFiles(tabId: tab.id)
                        },
                        onDownload: { items in
                            downloadFiles(items)
                        },
                        onEditFile: { item in
                            editRemoteFile(item, tab: tab)
                        },
                        onDelete: { item in
                            deleteRemoteItem(item, tabId: tab.id)
                        },
                        onRename: { item, newName in
                            renameRemoteItem(item, to: newName, tabId: tab.id)
                        },
                        onCreateFolder: { name in
                            createRemoteFolder(name, tabId: tab.id)
                        },
                        onListRemoteDirectory: { path in
                            guard let service = tab.sftpService else { return [] }
                            return try await service.listDirectoryNames(at: path)
                        },
                        onUploadFiles: { urls, targetPath in
                            guard let activeTab = tabManager.selectedTab else { return }
                            for url in urls {
                                let fileName = url.lastPathComponent
                                let remoteDest = targetPath.hasSuffix("/") ? targetPath + fileName : targetPath + "/" + fileName
                                self.transferManager.uploadFile(
                                    localPath: url.path,
                                    remotePath: remoteDest,
                                    fileName: fileName,
                                    connection: activeTab.connection,
                                    password: activeTab.password,
                                    tabId: activeTab.id
                                )
                            }
                        }
                    )
                } else {
                    emptyRemoteView
                }
            }
            .frame(minWidth: 300)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabManager.tabs) { tab in
                    tabButton(for: tab)
                }

                // Add tab button
                Button(action: { showConnectionSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("New connection")
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tabButton(for tab: RemoteTab) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tab.isConnected ? .green : .red)
                .frame(width: 6, height: 6)

            Text(tab.connection.displayName)
                .font(.system(size: 11))
                .lineLimit(1)

            Button(action: { tabManager.closeTab(tab.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(tabManager.selectedTabId == tab.id
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabManager.selectedTabId = tab.id
        }
    }

    private var emptyRemoteView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Not Connected")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Click Connect to start a session")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Transfer Buttons

    private var transferButtons: some View {
        VStack(spacing: 12) {
            Spacer()

            Button(action: {
                let selected = localFiles.filter { selectedLocalItems.contains($0.id) }
                if !selected.isEmpty {
                    uploadFiles(selected)
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                    Text("Upload")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(tabManager.hasAnyConnection ? .blue : .secondary)
            .disabled(!tabManager.hasAnyConnection)
            .help("Upload selected files to remote")

            Button(action: {
                guard let tab = tabManager.selectedTab else { return }
                let selected = tab.remoteFiles.filter { selectedRemoteItems.contains($0.id) }
                if !selected.isEmpty {
                    downloadFiles(selected)
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.system(size: 24))
                    Text("Download")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(tabManager.hasAnyConnection ? .green : .secondary)
            .disabled(!tabManager.hasAnyConnection)
            .help("Download selected files from remote")

            Spacer()
        }
        .frame(width: 60)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Actions

    private func connect(to connection: ServerConnection, password: String?) {
        let tabId = tabManager.addTab(connection: connection, password: password)
        let service = SFTPService(connection: connection, password: password)
        tabManager.updateTab(tabId) { $0.sftpService = service; $0.isLoadingRemote = true }

        Task {
            do {
                let connected = try await service.testConnection()
                if connected {
                    connectionManager.saveConnection(connection)
                    let home = try await service.homeDirectory()
                    let files = try await service.listFiles(at: home)
                    await MainActor.run {
                        tabManager.updateTab(tabId) {
                            $0.isConnected = true
                            $0.remotePath = home
                            $0.remoteFiles = files
                            $0.isLoadingRemote = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    tabManager.closeTab(tabId)
                }
            }
        }
    }

    private func disconnectActiveTab() {
        guard let tabId = tabManager.selectedTabId else { return }
        tabManager.closeTab(tabId)
    }

    private func refresh() {
        loadLocalFiles()
        if let tab = tabManager.selectedTab {
            loadRemoteFiles(tabId: tab.id)
        }
    }

    private func loadLocalFiles() {
        isLoadingLocal = true
        let path = localPath
        DispatchQueue.global().async {
            let items = FileHelper.listLocalFiles(at: path)
            DispatchQueue.main.async {
                localFiles = items
                isLoadingLocal = false
            }
        }
    }

    private func loadRemoteFiles(tabId: UUID) {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tabId }),
              let service = tabManager.tabs[index].sftpService else { return }
        let path = tabManager.tabs[index].remotePath
        tabManager.updateTab(tabId) { $0.isLoadingRemote = true }
        Task {
            do {
                let files = try await service.listFiles(at: path)
                await MainActor.run {
                    tabManager.updateTab(tabId) {
                        $0.remoteFiles = files
                        $0.isLoadingRemote = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to list remote files: \(error.localizedDescription)"
                    tabManager.updateTab(tabId) { $0.isLoadingRemote = false }
                }
            }
        }
    }

    private func uploadFiles(_ items: [FileItem]) {
        guard let tab = tabManager.selectedTab else { return }
        for item in items {
            let remoteDest = tab.remotePath.hasSuffix("/") ? tab.remotePath + item.name : tab.remotePath + "/" + item.name
            transferManager.uploadFile(
                localPath: item.fullPath,
                remotePath: remoteDest,
                fileName: item.name,
                connection: tab.connection,
                password: tab.password,
                tabId: tab.id
            )
        }
    }

    private func downloadFiles(_ items: [FileItem]) {
        guard let tab = tabManager.selectedTab else { return }
        for item in items {
            let localDest = localPath.hasSuffix("/") ? localPath + item.name : localPath + "/" + item.name
            transferManager.downloadFile(
                remotePath: item.fullPath,
                localPath: localDest,
                fileName: item.name,
                remoteSize: item.size,
                connection: tab.connection,
                password: tab.password,
                tabId: tab.id
            )
        }
    }

    private func deleteRemoteItem(_ item: FileItem, tabId: UUID) {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tabId }),
              let service = tabManager.tabs[index].sftpService else { return }
        Task {
            do {
                try await service.delete(at: item.fullPath, isDirectory: item.isDirectory)
                loadRemoteFiles(tabId: tabId)
            } catch {
                await MainActor.run {
                    errorMessage = "Delete failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func renameRemoteItem(_ item: FileItem, to newName: String, tabId: UUID) {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tabId }),
              let service = tabManager.tabs[index].sftpService else { return }
        let newPath = item.path.hasSuffix("/") ? item.path + newName : item.path + "/" + newName
        Task {
            do {
                try await service.rename(from: item.fullPath, to: newPath)
                loadRemoteFiles(tabId: tabId)
            } catch {
                await MainActor.run {
                    errorMessage = "Rename failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func editRemoteFile(_ item: FileItem, tab: RemoteTab) {
        let remotePath = item.fullPath
        let tempDir = NSTemporaryDirectory()
        let tempFile = (tempDir as NSString).appendingPathComponent("macscp_edit_\(UUID().uuidString)_\(item.name)")
        let sshTarget = tab.connection.sshTarget
        let scpPortArgs = tab.connection.scpPortArgs
        let escapedRemotePath = scpEscapeRemotePath(remotePath)
        let connection = tab.connection
        let password = tab.password

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            process.currentDirectoryURL = URL(fileURLWithPath: tempDir)

            var args: [String] = []
            args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
            args.append(contentsOf: scpPortArgs)
            args.append("\(sshTarget):\(escapedRemotePath)")
            args.append(tempFile)

            process.arguments = args

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed to download for editing: \(error.localizedDescription)"
                }
                return
            }

            process.waitUntilExit()

            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    do {
                        let content = try String(contentsOfFile: tempFile, encoding: .utf8)
                        try? FileManager.default.removeItem(atPath: tempFile)
                        editorFileName = item.name
                        editorRemotePath = remotePath
                        editorContent = content
                        editorConnection = connection
                        editorPassword = password
                        showEditor = true
                    } catch {
                        errorMessage = "Failed to read downloaded file: \(error.localizedDescription)"
                    }
                } else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    errorMessage = "Download for editing failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
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

    private func createRemoteFolder(_ name: String, tabId: UUID) {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tabId }),
              let service = tabManager.tabs[index].sftpService else { return }
        let path = tabManager.tabs[index].remotePath
        let folderPath = path.hasSuffix("/") ? path + name : path + "/" + name
        Task {
            do {
                try await service.createDirectory(at: folderPath)
                loadRemoteFiles(tabId: tabId)
            } catch {
                await MainActor.run {
                    errorMessage = "Create folder failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
