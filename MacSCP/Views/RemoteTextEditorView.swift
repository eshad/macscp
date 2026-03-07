import SwiftUI

struct RemoteTextEditorView: View {
    let fileName: String
    let remotePath: String
    let connection: ServerConnection
    let password: String?
    @Binding var isPresented: Bool

    @State private var content: String
    @State private var originalContent: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedSuccessfully = false

    init(fileName: String, remotePath: String, initialContent: String, connection: ServerConnection, password: String?, isPresented: Binding<Bool>) {
        self.fileName = fileName
        self.remotePath = remotePath
        self.connection = connection
        self.password = password
        self._isPresented = isPresented
        self._content = State(initialValue: initialContent)
        self._originalContent = State(initialValue: initialContent)
    }

    private var isDirty: Bool {
        content != originalContent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.blue)
            Text(fileName)
                .font(.headline)
            if isDirty {
                Text("(modified)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            if savedSuccessfully {
                Text("Saved")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            Spacer()
            Text(remotePath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var editor: some View {
        TextEditor(text: $content)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: content) { _ in
                savedSuccessfully = false
            }
    }

    private var footer: some View {
        HStack {
            if let err = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                saveFile()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!isDirty || isSaving)

            Button("Save & Close") {
                saveFile(closeAfter: true)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isDirty || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func saveFile(closeAfter: Bool = false) {
        isSaving = true
        savedSuccessfully = false
        errorMessage = nil

        let tempDir = NSTemporaryDirectory()
        let tempFile = (tempDir as NSString).appendingPathComponent("macscp_edit_\(UUID().uuidString)_\(fileName)")

        // Write content to temp file
        do {
            try content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Failed to write temp file: \(error.localizedDescription)"
            isSaving = false
            return
        }

        let sshTarget = connection.sshTarget
        let scpPortArgs = connection.scpPortArgs
        let escapedRemotePath = scpEscapeRemotePath(remotePath)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            process.currentDirectoryURL = URL(fileURLWithPath: tempDir)

            var args: [String] = []
            args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
            args.append(contentsOf: scpPortArgs)
            args.append(tempFile)
            args.append("\(sshTarget):\(escapedRemotePath)")

            process.arguments = args

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed to start upload: \(error.localizedDescription)"
                    isSaving = false
                }
                try? FileManager.default.removeItem(atPath: tempFile)
                return
            }

            process.waitUntilExit()

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: tempFile)

            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    originalContent = content
                    savedSuccessfully = true
                    isSaving = false
                    if closeAfter {
                        isPresented = false
                    }
                } else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    errorMessage = "Upload failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                    isSaving = false
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
}
