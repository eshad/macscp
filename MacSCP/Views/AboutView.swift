import SwiftUI

struct AboutView: View {
    @Binding var isPresented: Bool

    static let appVersion = "1.5.3"
    static let buildDate = "March 2026"

    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
                .padding(.top, 8)

            // App Name
            Text("MacSCP")
                .font(.system(size: 24, weight: .bold))

            // Version
            Text("Version \(Self.appVersion)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 24)

            // Description
            Text("A native macOS SFTP/SCP client for secure file transfers.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Version History
            VStack(alignment: .leading, spacing: 6) {
                Text("Version History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                versionEntry("1.5.3", "Fixed drag-drop stability and crash issues")
                versionEntry("1.5.0", "Navigation buttons and SCP path escaping")
                versionEntry("1.4.0", "Drag-drop animations and transfer UI improvements")
                versionEntry("1.3.0", "Drag-drop visual feedback and SSH input alignment")
                versionEntry("1.2.0", "Editable path bar with autocomplete suggestions")
                versionEntry("1.1.0", "SSH config host discovery for quick connect")
                versionEntry("1.0.0", "Initial release — SFTP browsing, transfers, text editor")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 20)

            Divider()
                .padding(.horizontal, 24)

            // Credits
            VStack(spacing: 4) {
                Text("Created By M.Hasan")
                    .font(.system(size: 12, weight: .medium))

                Text("Licensed free for macOS")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Close
            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .padding(.bottom, 8)
        }
        .frame(width: 380)
        .padding(.vertical, 12)
    }

    private func versionEntry(_ version: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("v\(version)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 42, alignment: .leading)
            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
