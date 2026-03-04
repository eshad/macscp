import SwiftUI

struct FileRowView: View {
    let item: FileItem
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: item.icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 20)

            // Name
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Size
            Text(item.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Date
            Text(item.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .trailing)

            // Permissions
            Text(item.permissions)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
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

// MARK: - Column Header

struct FileListHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)

            Text("Size")
                .frame(width: 70, alignment: .trailing)

            Text("Modified")
                .frame(width: 130, alignment: .trailing)

            Text("Permissions")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
