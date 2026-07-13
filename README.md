# TLG Launcher

A native macOS launcher and update manager for
[Cataclysm: The Last Generation](https://github.com/Cataclysm-TLG/Cataclysm-TLG).

- Installs and updates TLG from GitHub releases (SHA-256 verified, atomic
  activation, previous version kept for rollback).
- Never touches the canonical TLG user directory during updates; takes a full
  backup of it before each one.
- First-class font picker for interface, map and overmap typefaces, with
  import into the persistent user font directory and live preview.
- Colour scheme picker for the preset palettes the game ships in
  data/raw/color_themes, with a live preview of each.
- Bundles the TLG Hitchhiker's Guide, served to a WKWebView from a
  loopback-only HTTP server.
- Generates the guide's game data locally from the installed build (same
  format as RenechCDDA/tlg-data, verified equivalent), so the guide matches
  the version you play and works offline; falls back to the remote data
  otherwise.
- Backups and restore, with safety copies before every restore.

See `Docs/ARCHITECTURE.md` for design.

## Building

Requires macOS 14+ and the Xcode Command Line Tools (Swift 6+). No Xcode needed.

```sh
swift build                      # compile
swift run TLGLauncherChecks      # run the check suite
Scripts/build-guide.sh           # build ../tlg-guide and stage its dist/
Scripts/make-app.sh              # assemble dist/TLG Launcher.app (ad-hoc signed)
Scripts/make-dmg.sh              # package the app as a drag-to-install DMG
```

`swift run TLGLauncher` also works for development; the guide is picked up
from `GuideDist/` in the working directory.

## Credits

Cataclysm: The Last Generation is created by
[worm girl](https://www.youtube.com/@worm-girl) and contributors —
[cataclysmtlg.com](https://cataclysmtlg.com/),
[Cataclysm-TLG on GitHub](https://github.com/Cataclysm-TLG/Cataclysm-TLG).
The artwork shown in the launcher is from the TLG project. This launcher is
an independent fan tool, not an official TLG release.

## Licence

[CC BY-SA 4.0](LICENSE), matching the game's own CC-BY-SA licensing (the
repository redistributes TLG artwork, which stays under the game project's
terms and attribution).
