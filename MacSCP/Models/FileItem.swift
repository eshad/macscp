import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var path: String
    var size: Int64
    var modificationDate: Date?
    var permissions: String
    var isDirectory: Bool
    var isSymlink: Bool
    var owner: String
    var group: String

    init(
        name: String,
        path: String,
        size: Int64 = 0,
        modificationDate: Date? = nil,
        permissions: String = "",
        isDirectory: Bool = false,
        isSymlink: Bool = false,
        owner: String = "",
        group: String = ""
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.owner = owner
        self.group = group
    }

    var icon: String {
        if isDirectory { return "folder.fill" }
        if isSymlink { return "link" }

        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log", "csv":
            return "doc.text.fill"
        case "swift", "py", "js", "ts", "rb", "go", "rs", "c", "cpp", "h", "java":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "yaml", "yml", "toml", "plist":
            return "doc.badge.gearshape.fill"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "bmp", "tiff":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv", "webm":
            return "film.fill"
        case "mp3", "wav", "aac", "flac", "ogg":
            return "music.note"
        case "zip", "tar", "gz", "bz2", "xz", "rar", "7z":
            return "doc.zipper"
        case "pdf":
            return "doc.richtext.fill"
        case "sh", "bash", "zsh":
            return "terminal.fill"
        case "conf", "cfg", "ini", "env":
            return "gearshape.fill"
        default:
            return "doc.fill"
        }
    }

    var iconColor: String {
        if isDirectory { return "blue" }
        if isSymlink { return "purple" }

        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "orange"
        case "py": return "green"
        case "js", "ts": return "yellow"
        case "rb": return "red"
        case "png", "jpg", "jpeg", "gif", "svg": return "pink"
        case "zip", "tar", "gz": return "gray"
        default: return "secondary"
        }
    }

    var formattedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modificationDate else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var isEditableText: Bool {
        if isDirectory { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        let textExtensions: Set<String> = [
            "txt", "md", "log", "csv", "json", "xml", "yaml", "yml", "toml", "plist",
            "swift", "py", "js", "ts", "rb", "go", "rs", "c", "cpp", "h", "java",
            "sh", "bash", "zsh", "conf", "cfg", "ini", "env",
            "html", "css", "scss", "less", "php", "pl", "lua", "r",
            "sql", "makefile", "dockerfile", "gitignore",
            "kt", "scala", "ex", "exs", "erl", "hs", "ml",
            "vim", "fish", "ps1", "bat", "cmd"
        ]
        if textExtensions.contains(ext) { return true }
        // Also match dotfiles with no extension (e.g. .bashrc, .zshrc)
        if ext.isEmpty && name.hasPrefix(".") && name.count > 1 { return true }
        return false
    }

    var fullPath: String {
        if path.hasSuffix("/") {
            return path + name
        }
        return path + "/" + name
    }

    /// Parent directory path
    static func parentPath(of path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if components.count <= 1 { return "/" }
        return "/" + components.dropLast().joined(separator: "/")
    }
}
