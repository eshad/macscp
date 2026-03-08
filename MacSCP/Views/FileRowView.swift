import SwiftUI

class ColumnWidths: ObservableObject {
    @Published var size: CGFloat = 70
    @Published var modified: CGFloat = 130
    @Published var permissions: CGFloat = 90

    static let minSize: CGFloat = 50
    static let minModified: CGFloat = 80
    static let minPermissions: CGFloat = 60
}

struct FileRowView: View {
    let item: FileItem
    var isSelected: Bool = false
    var isDropTarget: Bool = false
    @EnvironmentObject var columnWidths: ColumnWidths

    var body: some View {
        HStack(spacing: 0) {
            // Icon + Name
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .frame(width: 20)

                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size
            Text(item.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: columnWidths.size, alignment: .trailing)
                .padding(.horizontal, 4)

            // Date
            Text(item.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: columnWidths.modified, alignment: .trailing)
                .padding(.horizontal, 4)

            // Permissions
            Text(item.permissions)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: columnWidths.permissions, alignment: .trailing)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(rowBackground)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(isDropTarget ? 1 : 0)
        )
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.15)
        } else if isSelected {
            return Color.accentColor.opacity(0.2)
        }
        return Color.clear
    }

    private var iconColor: Color {
        switch item.iconColor {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        case "pink": return .pink
        case "purple": return .purple
        case "gray": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Drag Preview

struct DragPreviewView: View {
    let name: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            // "+" badge
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 16, height: 16)
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(x: 8, y: -8),
            alignment: .topTrailing
        )
        .shadow(radius: 3)
    }
}

// MARK: - Column Header

struct FileListHeader: View {
    @EnvironmentObject var columnWidths: ColumnWidths
    @State private var dragStartSize: CGFloat = 0
    @State private var dragStartModified: CGFloat = 0
    @State private var dragStartPermissions: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)

            ColumnDragHandle()
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartSize == 0 { dragStartSize = columnWidths.size }
                            columnWidths.size = max(ColumnWidths.minSize, dragStartSize - value.translation.width)
                        }
                        .onEnded { _ in dragStartSize = 0 }
                )

            Text("Size")
                .frame(width: columnWidths.size, alignment: .trailing)
                .padding(.horizontal, 4)

            ColumnDragHandle()
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartModified == 0 { dragStartModified = columnWidths.modified }
                            columnWidths.modified = max(ColumnWidths.minModified, dragStartModified - value.translation.width)
                        }
                        .onEnded { _ in dragStartModified = 0 }
                )

            Text("Modified")
                .frame(width: columnWidths.modified, alignment: .trailing)
                .padding(.horizontal, 4)

            ColumnDragHandle()
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartPermissions == 0 { dragStartPermissions = columnWidths.permissions }
                            columnWidths.permissions = max(ColumnWidths.minPermissions, dragStartPermissions - value.translation.width)
                        }
                        .onEnded { _ in dragStartPermissions = 0 }
                )

            Text("Permissions")
                .frame(width: columnWidths.permissions, alignment: .trailing)
                .padding(.horizontal, 4)
        }
        .font(.caption.bold())
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ColumnDragHandle: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 14)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 12, height: 20)
                .contentShape(Rectangle())
                .cursor(.resizeLeftRight)
        }
        .frame(width: 12, height: 20)
    }
}

// MARK: - Key Event Handler

struct KeyEventHandler: NSViewRepresentable {
    let onSelectAll: () -> Void
    let onDelete: () -> Void
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onReturn: (() -> Void)?

    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.onSelectAll = onSelectAll
        view.onDelete = onDelete
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ nsView: KeyEventView, context: Context) {
        nsView.onSelectAll = onSelectAll
        nsView.onDelete = onDelete
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onReturn = onReturn
    }

    class KeyEventView: NSView {
        var onSelectAll: (() -> Void)?
        var onDelete: (() -> Void)?
        var onArrowUp: (() -> Void)?
        var onArrowDown: (() -> Void)?
        var onReturn: (() -> Void)?
        var isHovered = false
        private var monitor: Any?
        private var trackingArea: NSTrackingArea?

        /// Find the top-level panel ancestor (the outermost view within the split)
        private func panelBounds() -> NSRect? {
            // Walk up to find a sizeable parent that represents the panel
            var current: NSView? = superview
            while let view = current {
                if view.frame.height > 200 && view.frame.width > 100 {
                    return view.convert(view.bounds, to: nil)
                }
                current = view.superview
            }
            return nil
        }

        private func isMouseInsidePanel() -> Bool {
            guard let window = self.window else { return false }
            let mouseLocation = window.mouseLocationOutsideOfEventStream
            if let panelRect = panelBounds() {
                return panelRect.contains(mouseLocation)
            }
            return false
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            // Track mouse on the full window area - we check panel bounds in the handler
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self = self,
                          self.window?.isKeyWindow == true,
                          self.isMouseInsidePanel() else { return event }

                    // Check if a text field has focus — if so, don't intercept
                    if let responder = self.window?.firstResponder,
                       responder is NSTextView || responder is NSTextField {
                        // Only handle Cmd+A in text fields (let system handle it)
                        return event
                    }

                    // Cmd+A: select all
                    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "a" {
                        self.onSelectAll?()
                        return nil
                    }

                    // Delete / Backspace
                    if event.keyCode == 51 || event.keyCode == 117 {
                        self.onDelete?()
                        return nil
                    }

                    // Arrow Up (keyCode 126)
                    if event.keyCode == 126 {
                        self.onArrowUp?()
                        return nil
                    }

                    // Arrow Down (keyCode 125)
                    if event.keyCode == 125 {
                        self.onArrowDown?()
                        return nil
                    }

                    // Return / Enter (keyCode 36 or 76)
                    if event.keyCode == 36 || event.keyCode == 76 {
                        self.onReturn?()
                        return nil
                    }

                    return event
                }
            }
        }

        override func removeFromSuperview() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            super.removeFromSuperview()
        }
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
