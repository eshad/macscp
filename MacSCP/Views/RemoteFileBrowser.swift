import SwiftUI
import UniformTypeIdentifiers

struct RemoteFileBrowser: View {
    @Binding var currentPath: String
    @Binding var files: [FileItem]
    @Binding var isLoading: Bool
    let isConnected: Bool
    @State private var selectedItems: Set<FileItem> = []
    @State private var showNewFolderSheet = false
    @State private var newFolderName = ""
    @State private var renamingItem: FileItem?
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: FileItem?
    @State private var sortOrder: SortOrder = .name
    @State private var dropTargetItemId: UUID?
    @State private var isDropTargeted = false

    var onNavigate: (String) -> Void
    var onDownload: ([FileItem]) -> Void
    var onDelete: (FileItem) -> Void
    var onRename: (FileItem, String) -> Void
    var onCreateFolder: (String) -> Void
    var onListRemoteDirectory: ((String) async throws -> [String])?
    var onUploadFiles: (([URL], String) -> Void)?

    enum SortOrder {
        case name, size, date
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.green)
                Text("Remote Files")
                    .font(.headline)
                Spacer()

                if isConnected {
                    Button(action: { showNewFolderSheet = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Folder (Cmd+N)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            if !isConnected {
                notConnectedView
            } else {
                // Path bar with autocomplete
                PathBarView(path: currentPath, isRemote: true, onNavigate: { path in
                    onNavigate(path)
                }, onListRemoteDirectory: onListRemoteDirectory)

                Divider()
                FileListHeader()
                Divider()

                // File list
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                        .scaleEffect(0.8)
                    Spacer()
                } else {
                    fileList
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showNewFolderSheet) {
            newFolderSheet
        }
        .sheet(item: $renamingItem) { item in
            renameSheet(item: item)
        }
        .alert("Delete Item", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    onDelete(item)
                }
            }
        } message: {
            if let item = itemToDelete {
                Text("Are you sure you want to delete \"\(item.name)\"?\(item.isDirectory ? " This will delete all contents." : "")")
            }
        }
    }

    // MARK: - Subviews

    private var notConnectedView: some View {
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
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Parent directory
                if currentPath != "/" {
                    FileRowView(
                        item: FileItem(name: "..", path: currentPath, isDirectory: true)
                    )
                    .onTapGesture(count: 2) {
                        let parent = FileItem.parentPath(of: currentPath)
                        onNavigate(parent)
                    }
                    Divider().padding(.leading, 36)
                }

                ForEach(sortedFiles) { item in
                    if renamingItem?.id == item.id {
                        inlineRenameRow(item: item)
                    } else {
                        fileRow(item)
                    }

                    if item != sortedFiles.last {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { isDropTargeted },
            set: { val in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDropTargeted = val
                }
            }
        )) { providers in
            handleUploadDrop(providers, targetPath: currentPath)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.green, lineWidth: 3)
                .opacity(isDropTargeted ? 1 : 0)
                .padding(3)
                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        )
        .overlay(
            // Drop zone indicator
            VStack {
                Spacer()
                if isDropTargeted {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.doc.fill")
                            .foregroundColor(.green)
                        Text("Drop to upload here")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                }
            }
            .animation(.spring(response: 0.3), value: isDropTargeted)
        )
    }

    private func fileRow(_ item: FileItem) -> some View {
        FileRowView(
            item: item,
            isSelected: selectedItems.contains(item),
            isDropTarget: dropTargetItemId == item.id
        )
        .onTapGesture {
            handleTap(item)
        }
        .onTapGesture(count: 2) {
            handleDoubleTap(item)
        }
        .contextMenu {
            remoteContextMenu(for: item)
        }
        .itemProvider {
            // Provide remote path as text for cross-pane drag
            let provider = NSItemProvider()
            provider.registerItem(forTypeIdentifier: UTType.utf8PlainText.identifier) { completion, _, _ in
                completion?(item.fullPath as NSString, nil)
            }
            return provider
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { dropTargetItemId == item.id },
            set: { val in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if val { dropTargetItemId = item.id } else if dropTargetItemId == item.id { dropTargetItemId = nil }
                }
            }
        )) { providers in
            guard item.isDirectory else { return false }
            return handleUploadDrop(providers, targetPath: item.fullPath)
        }
    }

    private var sortedFiles: [FileItem] {
        files.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortOrder {
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size:
                return a.size > b.size
            case .date:
                return (a.modificationDate ?? .distantPast) > (b.modificationDate ?? .distantPast)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func remoteContextMenu(for item: FileItem) -> some View {
        Button("Download") {
            onDownload([item])
        }

        Divider()

        Button("Rename") {
            renameText = item.name
            renamingItem = item
        }

        Button("New Folder") {
            showNewFolderSheet = true
        }

        Divider()

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.fullPath, forType: .string)
        }

        Divider()

        Button("Delete", role: .destructive) {
            itemToDelete = item
            showDeleteConfirm = true
        }
    }

    // MARK: - Inline Rename

    private func inlineRenameRow(item: FileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 20)

            TextField("Name", text: $renameText, onCommit: {
                if !renameText.isEmpty && renameText != item.name {
                    onRename(item, renameText)
                }
                renamingItem = nil
            })
            .textFieldStyle(.roundedBorder)

            Button("Cancel") {
                renamingItem = nil
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Sheets

    private var newFolderSheet: some View {
        VStack(spacing: 16) {
            Text("New Folder")
                .font(.headline)

            TextField("Folder Name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack {
                Button("Cancel") {
                    showNewFolderSheet = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    if !newFolderName.isEmpty {
                        onCreateFolder(newFolderName)
                        newFolderName = ""
                        showNewFolderSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderName.isEmpty)
            }
        }
        .padding(24)
    }

    private func renameSheet(item: FileItem) -> some View {
        VStack(spacing: 16) {
            Text("Rename")
                .font(.headline)

            TextField("New Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack {
                Button("Cancel") {
                    renamingItem = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    if !renameText.isEmpty && renameText != item.name {
                        onRename(item, renameText)
                    }
                    renamingItem = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.isEmpty)
            }
        }
        .padding(24)
    }

    // MARK: - Actions

    private func handleTap(_ item: FileItem) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
        } else {
            selectedItems = [item]
        }
    }

    private func handleDoubleTap(_ item: FileItem) {
        if item.isDirectory {
            onNavigate(item.fullPath)
            selectedItems.removeAll()
        } else {
            onDownload([item])
        }
    }

    private func handleUploadDrop(_ providers: [NSItemProvider], targetPath: String) -> Bool {
        guard let onUploadFiles = onUploadFiles else { return false }
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    var url: URL?
                    if let urlData = data as? Data {
                        url = URL(dataRepresentation: urlData, relativeTo: nil)
                    } else if let rawURL = data as? URL {
                        url = rawURL
                    }
                    guard let sourceURL = url else { return }
                    DispatchQueue.main.async {
                        onUploadFiles([sourceURL], targetPath)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
