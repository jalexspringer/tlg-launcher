# TLG Launcher

A native macOS launcher and update manager for
[Cataclysm: The Last Generation](https://github.com/Cataclysm-TLG/Cataclysm-TLG).

- Installs and updates TLG from GitHub releases (SHA-256 verified, atomic
  activation, previous version kept for rollback).
- Never touches the canonical TLG user directory during updates; takes a full
  backup of it before each one.
- First-class font picker for interface, map and overmap typefaces, with
  import into the persistent user font directory and live preview.
- Bundles the TLG Hitchhiker's Guide, served to a WKWebView from a
  loopback-only HTTP server.
- Backups and restore, with safety copies before every restore.

See `Docs/ARCHITECTURE.md` for design. British English throughout.

## Building

Requires macOS 14+ and the Xcode Command Line Tools (Swift 6+). No Xcode needed.

```sh
swift build                      # compile
swift run TLGLauncherChecks      # run the check suite
Scripts/build-guide.sh           # build ../tlg-guide and stage its dist/
Scripts/make-app.sh              # assemble dist/TLG Launcher.app (ad-hoc signed)
```

`swift run TLGLauncher` also works for development; the guide is picked up
from `GuideDist/` in the working directory.
