import SwiftUI
import UniformTypeIdentifiers

struct LocalFileBrowser: View {
    @Binding var currentPath: String
    @Binding var files: [FileItem]
    @Binding var isLoading: Bool
    @State private var selectedItems: Set<FileItem> = []
    @State private var sortOrder: SortOrder = .name
    @State private var dropTargetItemId: UUID?
    @State private var isDropTargeted = false
    @State private var dropAnimating = false

    var onNavigate: (String) -> Void
    var onUpload: ([FileItem]) -> Void

    enum SortOrder {
        case name, size, date
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "laptopcomputer")
                    .foregroundColor(.accentColor)
                Text("Local Files")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            // Path bar with autocomplete
            PathBarView(path: currentPath, isRemote: false) { path in
                onNavigate(path)
            }

            Divider()
            FileListHeader()
            Divider()

            // File list
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else {
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
                                localContextMenu(for: item)
                            }
                            .itemProvider {
                                // Provide as file URL for cross-pane and Finder compatibility
                                let provider = NSItemProvider()
                                let url = URL(fileURLWithPath: item.fullPath)
                                provider.registerFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                                    completion(url, true, nil)
                                    return nil
                                }
                                // Also register as plain text for internal drag
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
                                return handleFileDrop(providers, targetPath: item.fullPath)
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
                    handleFileDrop(providers, targetPath: currentPath)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 3)
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
                                Image(systemName: "arrow.down.doc.fill")
                                    .foregroundColor(.accentColor)
                                Text("Drop to copy here")
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(6)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 8)
                        }
                    }
                    .animation(.spring(response: 0.3), value: isDropTargeted)
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // Handle drops from Finder, remote pane, or any file URL source
    private func handleFileDrop(_ providers: [NSItemProvider], targetPath: String) -> Bool {
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
                        let destPath = (targetPath as NSString).appendingPathComponent(sourceURL.lastPathComponent)
                        // Copy file from source to local target
                        if sourceURL.path != destPath {
                            try? FileManager.default.copyItem(atPath: sourceURL.path, toPath: destPath)
                            onNavigate(currentPath) // Refresh
                        }
                    }
                }
                handled = true
            }
        }
        return handled
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
        }
    }

    @ViewBuilder
    private func localContextMenu(for item: FileItem) -> some View {
        Button("Upload to Remote") {
            onUpload([item])
        }
        .disabled(false)

        Divider()

        Button("Open in Finder") {
            NSWorkspace.shared.selectFile(item.fullPath, inFileViewerRootedAtPath: currentPath)
        }

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.fullPath, forType: .string)
        }

        Divider()

        Button("Delete", role: .destructive) {
            deleteLocalItem(item)
        }
    }

    private func deleteLocalItem(_ item: FileItem) {
        do {
            try FileManager.default.removeItem(atPath: item.fullPath)
            onNavigate(currentPath) // Refresh
        } catch {
            // Error will be shown via alert in parent
        }
    }
}

// MARK: - Breadcrumb

struct BreadcrumbView: View {
    let path: String
    let onNavigate: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Button("/") {
                    onNavigate("/")
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundColor(.accentColor)

                ForEach(pathComponents.indices, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Button(pathComponents[index]) {
                        let targetPath = "/" + pathComponents[0...index].joined(separator: "/")
                        onNavigate(targetPath)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(index == pathComponents.count - 1 ? .primary : .accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var pathComponents: [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
