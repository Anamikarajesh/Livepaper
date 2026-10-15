# LivePaper

LivePaper is a local macOS menu bar app that lets you use one of your own videos as a live wallpaper experience.

It supports two related workflows:

- A live lock-screen wallpaper that reuses macOS's existing Aerial wallpaper infrastructure.
- An optional live desktop wallpaper that plays behind Finder and pauses when it would waste battery.

LivePaper is intentionally small, local, and native. It is built with Swift Package Manager and AppKit, without Electron, web views, or external package dependencies.

## Status

LivePaper is a personal macOS utility and should be treated as experimental software.

macOS does not expose a public API for setting an arbitrary custom video as a lock-screen live wallpaper. LivePaper works around that limitation by replacing the local video file for an existing Apple Aerial asset and then pointing the wallpaper store at that trusted asset ID. This is useful, but it depends on private macOS wallpaper implementation details that may change in future macOS releases.

The app was developed for modern macOS versions with the Aerial wallpaper system available. The package currently declares a minimum target of macOS 14.

## Features

- Choose a local `.mov`, `.mp4`, or QuickTime-compatible video.
- Install the selected video as a live lock-screen wallpaper.
- Re-encode the selected video into a wallpaper-friendly HEVC `.mov`.
- Loop or trim the source video into a prepared 120-second lock-screen asset.
- Replace a trusted local Apple Aerial asset rather than adding rejected custom manifest entries.
- Patch the per-user wallpaper store so lock screen and desktop sections reference the selected asset consistently.
- Back up edited wallpaper files before replacing them.
- Install a LaunchAgent that repairs the wallpaper if macOS restores or rewrites it.
- Apply a static desktop wallpaper from any frame in the selected video.
- Optionally enable a live desktop wallpaper using a desktop-level AppKit window and muted `AVQueuePlayer`.
- Pause and hide the live desktop wallpaper when another app is active.
- Pause the live desktop wallpaper below a configurable battery threshold.

## Download And Install

If you have a packaged release, download the latest DMG from the GitHub release or build artifact, then:

1. Open `LivePaper-<version>-macOS.dmg`.
2. Drag `LivePaper.app` into `Applications`.
3. Launch `LivePaper` from `Applications`.
4. If macOS Gatekeeper blocks the first launch because the app is locally signed, right-click the app, choose **Open**, then confirm.

The current packaging script uses ad-hoc local signing. It does not notarize the app with Apple.

## Build From Source

Requirements:

- macOS 14 or newer.
- Xcode command line tools.
- Swift 6-compatible toolchain.

Install command line tools if needed:

```bash
xcode-select --install
```

Build the app bundle:

```bash
bash scripts/package_app.sh
```

The app bundle is written to:

```text
dist/LivePaper.app
```

Build the DMG:

```bash
bash scripts/package_dmg.sh
```

The DMG is written to:

```text
dist/LivePaper-0.2.0-macOS.dmg
```

## GitHub Build

This repository includes a GitHub Actions workflow at `.github/workflows/build.yml`.

The workflow:

- Checks out the repository.
- Prints the Swift toolchain version.
- Runs `bash scripts/package_dmg.sh`.
- Uploads the generated DMG as a workflow artifact.

You can run it automatically on pushes and pull requests, or manually from the **Actions** tab with **Run workflow**.

## Usage

1. Launch `LivePaper`.
2. Open the menu bar item named **LivePaper**.
3. Choose **Settings...**.
4. Click **Choose Video...** and select a local video.
5. Move the **Static Frame** slider to choose the still frame used for the normal desktop wallpaper.
6. Click **Install Live Lock Screen** to install the selected video as the lock-screen live wallpaper.
7. Optionally enable **Live Home Screen** to play the selected video behind Finder.
8. Adjust **Pause Below** to choose the battery threshold for live desktop playback.

The menu bar also includes:

- **Install Live Lock Screen**: prepares and installs the selected video.
- **Repair Lock Screen Now**: reapplies the prepared video and wallpaper store changes.
- **Apply Static Desktop**: extracts and applies the selected still frame.
- **Enable Auto Repair**: installs the LaunchAgent repair helper.
- **Quit LivePaper**: exits the menu bar app.

## Command Line Modes

The packaged executable also supports helper modes:

```bash
/Applications/LivePaper.app/Contents/MacOS/LivePaper --install-lockscreen-aerial
/Applications/LivePaper.app/Contents/MacOS/LivePaper --repair-lockscreen-aerial
/Applications/LivePaper.app/Contents/MacOS/LivePaper --install-repair-agent
/Applications/LivePaper.app/Contents/MacOS/LivePaper --uninstall-repair-agent
/Applications/LivePaper.app/Contents/MacOS/LivePaper --apply-static
```

These commands use the same saved settings as the menu bar app.

## How It Works

LivePaper stores the selected source video path and user preferences in `UserDefaults`.

When installing the lock-screen wallpaper, the app:

1. Finds the user's Aerial wallpaper directory.
2. Reads the existing Apple Aerial manifest.
3. Chooses a trusted Apple asset that already has a local `.mov`.
4. Removes old `LIVEPAPER_` manifest entries left by earlier experimental builds.
5. Re-encodes the selected video into a prepared HEVC movie.
6. Backs up the wallpaper store and target Aerial video.
7. Replaces the trusted Aerial video's local file with the prepared movie.
8. Marks the replaced video as user-immutable with `chflags uchg`.
9. Patches the wallpaper store so relevant `Idle`, `Desktop`, and `Linked` sections point at the trusted asset.
10. Restarts wallpaper services so macOS picks up the change.

For live desktop playback, LivePaper does not patch the macOS wallpaper database. It creates one borderless desktop-level window per screen, loops the selected video with `AVPlayerLooper`, ignores mouse events, and hides the windows when the frontmost app is not Finder or LivePaper.

## Files LivePaper Reads Or Writes

LivePaper writes its own cache and logs under:

```text
~/Library/Application Support/LivePaper/
```

The prepared lock-screen movie is stored at:

```text
~/Library/Application Support/LivePaper/lockscreen-prepared.mov
```

The repair helper logs are stored at:

```text
~/Library/Application Support/LivePaper/repair-agent.out.log
~/Library/Application Support/LivePaper/repair-agent.err.log
```

The auto-repair LaunchAgent is installed at:

```text
~/Library/LaunchAgents/local.livepaper.repair.plist
```

LivePaper also edits the user's macOS wallpaper data:

```text
~/Library/Application Support/com.apple.wallpaper/aerials/videos/<ASSET-ID>.mov
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
```

Backups are written next to edited files with a `.livepaper-backup-<timestamp>` suffix.

## Uninstall

Quit LivePaper first.

Unload and remove the repair LaunchAgent:

```bash
/Applications/LivePaper.app/Contents/MacOS/LivePaper --uninstall-repair-agent
```

Remove the application:

```bash
rm -rf /Applications/LivePaper.app
```

Remove LivePaper's support files:

```bash
rm -rf "$HOME/Library/Application Support/LivePaper"
```

If you want to undo the lock-screen replacement, restore one of the `.livepaper-backup-<timestamp>` files that LivePaper created beside the modified Aerial video and wallpaper store. You can also change your wallpaper in System Settings and let macOS download a fresh Apple Aerial asset.

If a replaced Aerial video is locked, clear the immutable flag first:

```bash
chflags nouchg "$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos/<ASSET-ID>.mov"
```

## Troubleshooting

### `swift build` fails

Make sure Xcode command line tools are installed:

```bash
xcode-select --install
```

Then check the Swift version:

```bash
swift --version
```

### The app opens but there is no menu bar item

LivePaper runs as an accessory/menu bar app. Look for **LivePaper** in the macOS menu bar. If the menu bar is crowded, quit a few menu bar apps or check the hidden overflow area if your menu bar manager provides one.

### The lock screen does not change

Open LivePaper, choose the video again, and click **Repair Lock Screen Now**.

Also confirm that macOS has at least one Apple Aerial asset downloaded locally. LivePaper needs a trusted local Aerial `.mov` to replace. If none exist, choose and preview an Apple Aerial wallpaper in System Settings first so macOS downloads one.

### The desktop turns black after unlock

Click **Repair Lock Screen Now**. Earlier experimental approaches that added custom manifest entries could leave macOS pointing at rejected `LIVEPAPER_` assets. Current builds remove those stale entries and point wallpaper sections at an existing trusted Apple asset.

### The live desktop wallpaper stops playing

This is expected when:

- Battery is below the configured threshold.
- The frontmost app is not Finder or LivePaper.
- **Live Home Screen** is turned off.

### macOS restores the original Aerial video

Use **Enable Auto Repair** or run:

```bash
/Applications/LivePaper.app/Contents/MacOS/LivePaper --install-repair-agent
```

The LaunchAgent periodically repairs the wallpaper and watches key wallpaper paths.

### The first launch is blocked

The local build is ad-hoc signed but not notarized. Right-click `LivePaper.app`, choose **Open**, and confirm. For public distribution, sign with a Developer ID certificate and notarize the DMG.

## Repository Layout

```text
.
├── Package.swift
├── README.md
├── LIVEPAPER_PROJECT_REPORT.md
├── Sources/
│   └── LivePaper/
│       ├── AerialWallpaperInstaller.swift
│       ├── AppDelegate.swift
│       ├── DesktopLiveWallpaperController.swift
│       ├── FrameExtractor.swift
│       ├── LaunchAgentInstaller.swift
│       ├── LayeredHEVCWriter.swift
│       ├── SettingsStore.swift
│       ├── SettingsWindowController.swift
│       ├── WallpaperController.swift
│       └── main.swift
├── scripts/
│   ├── package_app.sh
│   └── package_dmg.sh
└── .github/
    └── workflows/
        └── build.yml
```

## Distribution Notes

The default scripts are meant for local builds and GitHub artifacts:

- `scripts/package_app.sh` builds `dist/LivePaper.app`.
- `scripts/package_dmg.sh` builds `dist/LivePaper-<version>-macOS.dmg`.
- The app is ad-hoc signed with `codesign --sign -`.
- The DMG is not notarized.

For public releases, use a Developer ID Application certificate, sign the app, create the DMG, sign the DMG, submit it for notarization, and staple the notarization ticket.

## Privacy

LivePaper does not send your videos or settings to a server. The selected video path is saved locally in user defaults, and generated assets are kept under your local `~/Library/Application Support/LivePaper` directory.

The app does read and edit local wallpaper files in your home directory. Review the source before running it if you are uncomfortable with that.

## License

No license has been selected yet. Add a license before publishing the repository for public reuse or accepting contributions.
