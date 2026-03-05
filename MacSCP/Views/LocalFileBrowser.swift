import SwiftUI

struct LocalFileBrowser: View {
    @Binding var currentPath: String
    @Binding var files: [FileItem]
    @Binding var isLoading: Bool
    @State private var selectedItems: Set<FileItem> = []
    @State private var sortOrder: SortOrder = .name

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
                                isSelected: selectedItems.contains(item)
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
                            .draggable(item.fullPath) {
                                Label(item.name, systemImage: item.icon)
                                    .padding(4)
                            }

                            if item != sortedFiles.last {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
