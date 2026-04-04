# MacSCP

A native macOS SFTP/SCP client built with SwiftUI. Dual-pane file manager inspired by WinSCP — browse local and remote files side by side, transfer with drag-and-drop, and manage files on your servers.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Dual-Pane Browser** — Local files on the left, remote files on the right with breadcrumb navigation
- **Connection Manager** — Save and manage multiple server connections
- **SSH Key & Password Auth** — Uses ssh-agent keys or password via `SSH_ASKPASS`
- **File Transfers** — Upload and download with progress bars, speed, and ETA
- **File Operations** — Create folder, rename, delete, copy path on both local and remote
- **Drag & Drop** — Drag files between panes or from Finder into the remote pane
- **Context Menus** — Right-click for quick actions
- **Keyboard Shortcuts** — `Cmd+R` refresh, `Cmd+N` new folder

## Screenshot

```
┌─────────────────────────────────────────────────────┐
│  🔵 MacSCP          Connected: user@server  [Refresh]│
├────────────────────┬────────────────────────────────┤
│   LOCAL FILES      │      REMOTE FILES              │
│  /Users/you        │  /home/user                    │
│  ┌──────────────┐  │  ┌──────────────────────────┐  │
│  │ 📁 Documents │  │  │ 📁 projects              │  │
│  │ 📁 Downloads │  │  │ 📁 .ssh                  │  │
│  │ 📄 notes.txt │  │  │ 📄 .bashrc               │  │
│  └──────────────┘  │  └──────────────────────────┘  │
├────────────────────┴────────────────────────────────┤
│  Transfer Queue                                      │
│  ↑ uploading app.zip  ████████░░ 80%  2.1 MB/s      │
│  ↓ downloaded log.gz  ██████████ Done                │
└─────────────────────────────────────────────────────┘
```

## Requirements

- macOS 13.0 (Ventura) or later
- SSH client (`/usr/bin/ssh`, `/usr/bin/scp`) — included with macOS

No third-party dependencies. Uses the system SSH/SCP binaries via `Process`.

## Install

### From DMG

Download the latest `.dmg` from [Releases](https://github.com/eshad/macscp/releases), open it, and drag **MacSCP** to **Applications**.


## License

MIT
