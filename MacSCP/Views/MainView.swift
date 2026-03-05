import SwiftUI

struct MainView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var transferManager: TransferManager
    @State private var showConnectionSheet = false
    @State private var localPath = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var remotePath = "~"
    @State private var localFiles: [FileItem] = []
    @State private var remoteFiles: [FileItem] = []
    @State private var isLoadingLocal = false
    @State private var isLoadingRemote = false
    @State private var errorMessage: String?
    @State private var sftpService: SFTPService?
    @State private var transferQueueHeight: CGFloat = 160

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
        .onAppear {
            loadLocalFiles()
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        ToolbarView(
            isConnected: connectionManager.isConnected,
            connectionName: connectionManager.activeConnection?.displayName ?? "",
            onConnect: { showConnectionSheet = true },
            onDisconnect: disconnect,
            onRefresh: refresh
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

            RemoteFileBrowser(
                currentPath: $remotePath,
                files: $remoteFiles,
                isLoading: $isLoadingRemote,
                isConnected: connectionManager.isConnected,
                onNavigate: { path in
                    remotePath = path
                    loadRemoteFiles()
                },
                onDownload: { items in
                    downloadFiles(items)
                },
                onDelete: { item in
                    deleteRemoteItem(item)
                },
                onRename: { item, newName in
                    renameRemoteItem(item, to: newName)
                },
                onCreateFolder: { name in
                    createRemoteFolder(name)
                },
                onListRemoteDirectory: { path in
                    guard let service = sftpService else { return [] }
                    return try await service.listDirectoryNames(at: path)
                },
                onUploadFiles: { urls, targetPath in
                    for url in urls {
                        let fileName = url.lastPathComponent
                        let remoteDest = targetPath.hasSuffix("/") ? targetPath + fileName : targetPath + "/" + fileName
                        self.transferManager.uploadFile(
                            localPath: url.path,
                            remotePath: remoteDest,
                            fileName: fileName
                        )
                    }
                }
            )
            .frame(minWidth: 300)
        }
    }

    // MARK: - Actions

    private func connect(to connection: ServerConnection, password: String?) {
        let service = SFTPService(connection: connection, password: password)
        sftpService = service
        transferManager.configure(connection: connection, password: password)

        isLoadingRemote = true
        Task {
            do {
                let connected = try await service.testConnection()
                if connected {
                    connectionManager.setActive(connection)
                    let home = try await service.homeDirectory()
                    remotePath = home
                    let files = try await service.listFiles(at: home)
                    await MainActor.run {
                        remoteFiles = files
                        isLoadingRemote = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    isLoadingRemote = false
                }
            }
        }
    }

    private func disconnect() {
        connectionManager.disconnect()
        sftpService = nil
        remoteFiles = []
        remotePath = "~"
    }

    private func refresh() {
        loadLocalFiles()
        if connectionManager.isConnected {
            loadRemoteFiles()
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

    private func loadRemoteFiles() {
        guard let service = sftpService else { return }
        isLoadingRemote = true
        Task {
            do {
                let files = try await service.listFiles(at: remotePath)
                await MainActor.run {
                    remoteFiles = files
                    isLoadingRemote = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to list remote files: \(error.localizedDescription)"
                    isLoadingRemote = false
                }
            }
        }
    }

    private func uploadFiles(_ items: [FileItem]) {
        for item in items {
            let remoteDest = remotePath.hasSuffix("/") ? remotePath + item.name : remotePath + "/" + item.name
            transferManager.uploadFile(
                localPath: item.fullPath,
                remotePath: remoteDest,
                fileName: item.name
            )
        }
    }

    private func downloadFiles(_ items: [FileItem]) {
        for item in items {
            let localDest = localPath.hasSuffix("/") ? localPath + item.name : localPath + "/" + item.name
            transferManager.downloadFile(
                remotePath: item.fullPath,
                localPath: localDest,
                fileName: item.name,
                remoteSize: item.size
            )
        }
    }

    private func deleteRemoteItem(_ item: FileItem) {
        guard let service = sftpService else { return }
        Task {
            do {
                try await service.delete(at: item.fullPath, isDirectory: item.isDirectory)
                loadRemoteFiles()
            } catch {
                await MainActor.run {
                    errorMessage = "Delete failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func renameRemoteItem(_ item: FileItem, to newName: String) {
        guard let service = sftpService else { return }
        let newPath = item.path.hasSuffix("/") ? item.path + newName : item.path + "/" + newName
        Task {
            do {
                try await service.rename(from: item.fullPath, to: newPath)
                loadRemoteFiles()
            } catch {
                await MainActor.run {
                    errorMessage = "Rename failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func createRemoteFolder(_ name: String) {
        guard let service = sftpService else { return }
        let folderPath = remotePath.hasSuffix("/") ? remotePath + name : remotePath + "/" + name
        Task {
            do {
                try await service.createDirectory(at: folderPath)
                loadRemoteFiles()
            } catch {
                await MainActor.run {
                    errorMessage = "Create folder failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
