import Foundation

struct FileHelper {
    static func listLocalFiles(at path: String) -> [FileItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return []
        }

        var items: [FileItem] = []

        for name in contents {
            guard !name.hasPrefix(".") || name == ".ssh" else { continue } // Skip hidden except .ssh

            let fullPath = (path as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath) else { continue }

            let fileType = attrs[.type] as? FileAttributeType
            let isDirectory = fileType == .typeDirectory
            let isSymlink = fileType == .typeSymbolicLink
            let size = (attrs[.size] as? Int64) ?? 0
            let modDate = attrs[.modificationDate] as? Date
            let posix = attrs[.posixPermissions] as? Int ?? 0
            let owner = (attrs[.ownerAccountName] as? String) ?? ""
            let group = (attrs[.groupOwnerAccountName] as? String) ?? ""

            let perms = formatPermissions(posix, isDirectory: isDirectory, isSymlink: isSymlink)

            items.append(FileItem(
                name: name,
                path: path,
                size: size,
                modificationDate: modDate,
                permissions: perms,
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                owner: owner,
                group: group
            ))
        }

        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func formatPermissions(_ posix: Int, isDirectory: Bool, isSymlink: Bool) -> String {
        let type = isSymlink ? "l" : (isDirectory ? "d" : "-")
        let perms = [
            (posix & 0o400 != 0) ? "r" : "-",
            (posix & 0o200 != 0) ? "w" : "-",
            (posix & 0o100 != 0) ? "x" : "-",
            (posix & 0o040 != 0) ? "r" : "-",
            (posix & 0o020 != 0) ? "w" : "-",
            (posix & 0o010 != 0) ? "x" : "-",
            (posix & 0o004 != 0) ? "r" : "-",
            (posix & 0o002 != 0) ? "w" : "-",
            (posix & 0o001 != 0) ? "x" : "-",
        ]
        return type + perms.joined()
    }

    static func localHomeDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    static func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func createDirectory(at path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func deleteItem(at path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    static func fileSize(at path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }
}
