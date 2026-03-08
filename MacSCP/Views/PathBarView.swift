import SwiftUI

struct PathBarView: View {
    let path: String
    let isRemote: Bool
    let onNavigate: (String) -> Void
    var onListRemoteDirectory: ((String) async throws -> [String])?

    @State private var isEditing = false
    @State private var editText = ""
    @State private var suggestions: [PathSuggestion] = []
    @State private var showSuggestions = false
    @State private var selectedSuggestionIndex: Int = -1
    @FocusState private var isTextFieldFocused: Bool

    struct PathSuggestion: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let fullPath: String
        let isDirectory: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                editablePathBar
            } else {
                readOnlyPathBar
            }

            if showSuggestions && !suggestions.isEmpty {
                suggestionsList
            }
        }
    }

    // MARK: - Read-only path bar (click to edit)

    private var readOnlyPathBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text(path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "pencil")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .contentShape(Rectangle())
        .onTapGesture {
            editText = path
            isEditing = true
            isTextFieldFocused = true
            updateSuggestions()
        }
    }

    // MARK: - Editable path bar

    private var editablePathBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)

            PathTextField(
                text: $editText,
                isFocused: $isTextFieldFocused,
                onSubmit: {
                    if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
                        handleSuggestionTap(suggestions[selectedSuggestionIndex])
                    } else {
                        navigateToPath(editText)
                    }
                },
                onArrowUp: {
                    if showSuggestions && !suggestions.isEmpty {
                        selectedSuggestionIndex = max(selectedSuggestionIndex - 1, 0)
                    }
                },
                onArrowDown: {
                    if showSuggestions && !suggestions.isEmpty {
                        selectedSuggestionIndex = min(selectedSuggestionIndex + 1, suggestions.count - 1)
                    }
                },
                onEscape: {
                    cancelEditing()
                },
                onTextChange: {
                    selectedSuggestionIndex = -1
                    updateSuggestions()
                }
            )

            Button(action: { navigateToPath(editText) }) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Button(action: { cancelEditing() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Suggestions dropdown

    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    suggestionRow(suggestion, isSelected: index == selectedSuggestionIndex)

                    if suggestion.id != suggestions.last?.id {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    private func suggestionRow(_ suggestion: PathSuggestion, isSelected: Bool = false) -> some View {
        let iconName = suggestion.isDirectory ? "folder.fill" : "doc.fill"
        let iconColor: Color = suggestion.isDirectory ? .blue : .secondary

        return HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 16)

            Text(suggestion.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            Text(suggestion.fullPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(3)
        .onTapGesture {
            handleSuggestionTap(suggestion)
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func handleSuggestionTap(_ suggestion: PathSuggestion) {
        if suggestion.isDirectory {
            editText = suggestion.fullPath.hasSuffix("/") ? suggestion.fullPath : suggestion.fullPath + "/"
            updateSuggestions()
        } else {
            let parent = (suggestion.fullPath as NSString).deletingLastPathComponent
            navigateToPath(parent)
        }
    }

    // MARK: - Logic

    private func navigateToPath(_ rawPath: String) {
        var targetPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetPath.isEmpty { return }

        // Expand ~ for local paths
        if !isRemote && targetPath.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            targetPath = home + targetPath.dropFirst()
        }

        // Remove trailing slash (except root)
        if targetPath != "/" && targetPath.hasSuffix("/") {
            targetPath = String(targetPath.dropLast())
        }

        isEditing = false
        showSuggestions = false
        onNavigate(targetPath)
    }

    private func cancelEditing() {
        isEditing = false
        showSuggestions = false
        isTextFieldFocused = false
    }

    private func updateSuggestions() {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            suggestions = []
            showSuggestions = false
            return
        }

        if isRemote {
            updateRemoteSuggestions(text)
        } else {
            updateLocalSuggestions(text)
        }
    }

    // MARK: - Reset suggestion index on new suggestions
    private func resetSuggestionIndex() {
        selectedSuggestionIndex = -1
    }

    private func updateLocalSuggestions(_ text: String) {
        var expandedText = text
        if expandedText.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expandedText = home + expandedText.dropFirst()
        }

        let fm = FileManager.default
        let directoryToList: String
        let filterPrefix: String

        if expandedText.hasSuffix("/") {
            directoryToList = expandedText
            filterPrefix = ""
        } else {
            directoryToList = (expandedText as NSString).deletingLastPathComponent
            filterPrefix = (expandedText as NSString).lastPathComponent.lowercased()
        }

        guard fm.fileExists(atPath: directoryToList) else {
            suggestions = []
            showSuggestions = false
            return
        }

        DispatchQueue.global(qos: .userInteractive).async {
            guard let contents = try? fm.contentsOfDirectory(atPath: directoryToList) else {
                DispatchQueue.main.async {
                    suggestions = []
                    showSuggestions = false
                }
                return
            }

            var results: [PathSuggestion] = []
            for name in contents {
                guard !name.hasPrefix(".") else { continue }
                if !filterPrefix.isEmpty && !name.lowercased().hasPrefix(filterPrefix) { continue }

                let fullPath = (directoryToList as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                results.append(PathSuggestion(
                    name: name,
                    fullPath: fullPath,
                    isDirectory: isDir.boolValue
                ))

                if results.count >= 15 { break }
            }

            results.sort { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            DispatchQueue.main.async {
                suggestions = results
                showSuggestions = !results.isEmpty
            }
        }
    }

    private func updateRemoteSuggestions(_ text: String) {
        guard let listDir = onListRemoteDirectory else {
            showSuggestions = false
            return
        }

        let directoryToList: String
        let filterPrefix: String

        if text.hasSuffix("/") {
            directoryToList = text
            filterPrefix = ""
        } else {
            let parts = text.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count > 1 {
                directoryToList = "/" + parts.dropLast().joined(separator: "/")
                filterPrefix = String(parts.last ?? "").lowercased()
            } else {
                directoryToList = "/"
                filterPrefix = text.lowercased()
            }
        }

        Task {
            do {
                let dirs = try await listDir(directoryToList)
                var results: [PathSuggestion] = []
                for name in dirs {
                    if !filterPrefix.isEmpty && !name.lowercased().hasPrefix(filterPrefix) { continue }
                    let fullPath = directoryToList.hasSuffix("/")
                        ? directoryToList + name
                        : directoryToList + "/" + name
                    results.append(PathSuggestion(name: name, fullPath: fullPath, isDirectory: true))
                    if results.count >= 15 { break }
                }

                await MainActor.run {
                    suggestions = results
                    showSuggestions = !results.isEmpty
                }
            } catch {
                await MainActor.run {
                    suggestions = []
                    showSuggestions = false
                }
            }
        }
    }
}

// MARK: - Path Text Field with arrow key interception

struct PathTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onEscape: () -> Void
    var onTextChange: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = ArrowKeyTextField()
        field.delegate = context.coordinator
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.stringValue = text
        field.onArrowUp = onArrowUp
        field.onArrowDown = onArrowDown
        field.onEscapeKey = onEscape
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let field = nsView as? ArrowKeyTextField {
            field.onArrowUp = onArrowUp
            field.onArrowDown = onArrowDown
            field.onEscapeKey = onEscape
        }
        if isFocused.wrappedValue {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PathTextField

        init(_ parent: PathTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onTextChange()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown()
                return true
            }
            return false
        }
    }
}

class ArrowKeyTextField: NSTextField {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEscapeKey: (() -> Void)?
}
