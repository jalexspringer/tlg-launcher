# TLG Launcher — architecture

A native SwiftUI macOS launcher and update manager for Cataclysm: The Last
Generation. Minimum macOS 14 (needed for `@Observable`; nothing in scope needs
newer). Built as a SwiftPM package because this machine has Command Line Tools
only — no Xcode, no `xcodebuild`, and no XCTest/Swift Testing in the toolchain.
Consequences:

- The `.app` bundle is assembled by `Scripts/make-app.sh` (release binary +
  Info.plist + guide dist, ad-hoc signed), not by Xcode.
- Tests are a plain executable (`swift run TLGLauncherChecks`) with a ~60-line
  assertion runner. They port mechanically to Swift Testing if Xcode ever lands.

## Targets

- **TLGLauncherCore** — all behaviour, UI-free, fully testable.
- **TLGLauncher** — SwiftUI app: observable `AppModel` + one view per sidebar
  section (Play, Releases, Backups, Fonts, Guide, Settings).
- **TLGLauncherChecks** — the check suite (22 checks).

## Core services

| Service | Responsibility | External boundary |
|---|---|---|
| `GitHubReleaseClient` | Fetch/parse releases of `Cataclysm-TLG/Cataclysm-TLG` | `ReleaseFetching` protocol, URLSession |
| `AssetSelection` | Pick `ctlg-osx-tiles-universal-*.dmg`; order releases by `published_at` (several land per day) | pure |
| `URLSessionDownloader` | Stream download with progress | `Downloading` protocol |
| `SHA256Verifier` | Streaming digest; accepts GitHub's `sha256:<hex>` asset digest | pure |
| `HDIUtilMounter` | `hdiutil attach -readonly -nobrowse -plist` / `detach` (retry, then `-force`) | `DMGMounting` + `ProcessRunning` |
| `UpdateInstaller` | The update transaction (below) | composed of the above |
| `VersionStore` | `state.json` (active/previous tags), per-version metadata, rollback, pruning | filesystem |
| `BackupManager` | Timestamped full copies of the TLG user dir (APFS clones), restore with safety copy, auto-prune | filesystem |
| `GameProcessDetector` | `pgrep -f` on `cataclysm-tlg` / the Steam path — bundle id is useless, TLG shares `com.cataclysmdda.en.cataclysm` with CDDA | `ProcessRunning` |
| `GameLauncher` | Launch plan + spawn | pure planning, `Process` |
| `FontConfigStore` | `fonts.json` / `options.json` edits preserving unknown fields and order; backup before write; refuse while running | filesystem |
| `FontCatalog` | Bundled/imported/system font enumeration, import with collision handling | CoreText, filesystem |
| `GuideServer` | Loopback static server for the bundled guide | Network.framework |

`LauncherPaths` derives every path from two injectable roots (launcher support
dir, game user dir), so all filesystem tests run in temp directories. It also
enforces the core invariant: `assertOutsideGameUserData` throws if the
installer would touch `~/Library/Application Support/Cataclysm-TLG/`.

## The update transaction

```
refuse if game running
→ back up user data (BackupManager)
→ download to downloads/*.partial, promote on completion
→ verify SHA-256 against GitHub's asset digest (when present)
→ hdiutil attach read-only
→ copy Cataclysm.app to staging/install-<uuid>/
→ validate (Info.plist, executable CFBundleExecutable, tiles binary)
→ strip quarantine
→ detach
→ atomic rename staging → versions/<tag>/   ← the commit point
→ state.json: previous ← active, active ← tag
→ prune old versions (never active/previous) and old auto-backups
```

Any failure before the rename leaves the active version untouched; staging is
deleted and the DMG detached on all paths. Reinstalling an existing tag moves
the old copy aside and restores it if the swap fails.

Rollback (`VersionStore.rollback`) swaps active/previous tags only. Restoring
user data is a deliberately separate action in Backups, because saves opened
by a newer binary may not load in an older one — the UI warns about this.

## Launching the game

The release app's `CFBundleExecutable` is `Cataclysm.sh`, which `cd`s into
`Contents/Resources` and execs `./cataclysm-tlg-tiles` with `DYLD_LIBRARY_PATH=.`
— and does **not** forward arguments. So the launcher replicates the script:
it spawns `Contents/Resources/cataclysm-tlg-tiles` directly with that working
directory and environment, adding `--userdir "<canonical dir>/"` (trailing
slash required; TLG string-concatenates onto it).

## Fonts

`fonts.json` holds three typeface stacks (`typeface`, `map_typeface`,
`overmap_typeface`); first entry is primary, the rest are glyph fallbacks.
Dimensions/blending live as named string entries in `options.json`. Both files
are edited via `JSONSerialization` so unknown keys, unknown entries and entry
order all survive round-trips; both are backed up to `config-backups/` before
every write. Imported fonts are copied into the persistent user `font/` dir
and referenced by bare filename — TLG searches the user font dir before the
game's `data/font`, and the user dir survives updates.

## Bundled guide

`Scripts/build-guide.sh` builds the sibling `tlg-guide` repo (pinned Yarn 1,
frozen lockfile) and stages `dist/` into `GuideDist/`, which `make-app.sh`
copies into the app's Resources. `GuideServer` serves it over
`http://127.0.0.1:<ephemeral>` — GET/HEAD only, traversal rejected both by
component check and root-prefix check after standardisation, extensionless
routes fall back to `index.html` (Vite SPA), missing assets 404. The bundled
part is the guide **UI**; game data is still fetched live from
`RenechCDDA/tlg-data` (its GitHub Action aggregates each game release's JSON
into one `all.json`), so guide content tracks TLG releases without rebuilding.

## Layout on disk

```
~/Library/Application Support/TLG Launcher/
  state.json            active/previous tags
  versions/<tag>/       Cataclysm.app + .tlg-launcher-version.json
  staging/              transient install staging
  downloads/            transient DMGs
  backups/<stamp>/      metadata.json + UserData/ (full copy)
  config-backups/       fonts.json/options.json pre-write copies
```
