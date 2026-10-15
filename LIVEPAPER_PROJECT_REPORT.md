# LivePaper Project Report

## Project Summary

LivePaper is a personal macOS app experiment for using a small custom video as a live wallpaper. The target behavior is:

- The lock screen should always show a live wallpaper.
- The normal desktop/home screen should normally remain static.
- The user can optionally enable a live home-screen wallpaper.
- The live home-screen wallpaper should pause when battery is below a configurable threshold.
- The live home-screen wallpaper should pause/hide when another app is active, so it does not waste battery behind normal app windows.
- The app is intended for one personal Mac, not for App Store distribution.

The work was done on macOS Tahoe 26.5.1. This matters because the lock-screen wallpaper system in recent macOS versions is not exposed through a clean public API for arbitrary user-provided video wallpapers.

## Important Reality Check

macOS does not provide a normal public API for setting a fully custom live lock-screen wallpaper from a third-party app. Apple supports its own Aerial/dynamic wallpapers through internal wallpaper infrastructure, but arbitrary apps cannot simply call a supported API like:

```swift
setLockScreenLiveWallpaper(videoURL)
```

Because of this limitation, LivePaper uses a workaround:

1. Use an existing Apple Aerial wallpaper asset slot.
2. Replace that asset's local `.mov` file with the user's prepared video.
3. Patch the user's wallpaper store so the lock screen points at that trusted Apple asset ID.
4. Keep repairing the asset because macOS may revert, re-download, or rewrite wallpaper files.

This approach is powerful, but fragile. macOS updates may break it. Wallpaper internals can change. The project is best understood as a personal utility/hack rather than a fully supported macOS wallpaper product.

## Main Components

The project was structured as a Swift Package app named `LivePaper`.

Expected project layout:

```text
Package.swift
README.md
scripts/package_app.sh
Sources/LivePaper/
  AppDelegate.swift
  SettingsStore.swift
  SettingsWindowController.swift
  WallpaperController.swift
  FrameExtractor.swift
  AerialWallpaperInstaller.swift
  LayeredHEVCWriter.swift
  LaunchAgentInstaller.swift
  DesktopLiveWallpaperController.swift
```

The packaged app output is:

```text
dist/LivePaper.app
```

## User-Facing Features Built

### 1. Video Selection

The app lets the user choose a source video file. The selected video path is stored in `UserDefaults`.

The test video used during development was:

```text
/Users/anamikarajesh/Downloads/ad249c50-39c0-48f4-b72d-02e9e4c4afe9.mp4
```

That video was approximately:

- 3840x2160
- 22 seconds
- H.264 video
- AAC audio

Audio is ignored for wallpaper use.

### 2. Static Desktop Wallpaper

For the normal desktop, LivePaper can extract a selected frame from the chosen video and set it as the desktop wallpaper.

The selected frame time is controlled by a slider in the settings window.

Earlier issue:

- The static wallpaper did not fill the whole screen.
- macOS was applying it with a scaling mode that could leave empty space.

Fix:

- Generate an aspect-fill still image at the screen's pixel size.
- Apply it using a scaling mode that fills the screen dimensions.

### 3. Live Lock-Screen Wallpaper

This is the hardest part of the project.

LivePaper patches macOS's wallpaper system by using an existing local Apple Aerial asset. The final active asset ID used during development was:

```text
4C108785-A7BA-422E-9C79-B0129F1D5550
```

Earlier asset IDs also appeared during testing, including:

```text
6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7
A77E8F84-B2B1-4E39-B63A-3F4ED99B5D42
```

The lock-screen video path used by macOS is inside:

```text
~/Library/Application Support/com.apple.wallpaper/aerials/videos/
```

The prepared LivePaper cache is stored at:

```text
~/Library/Application Support/LivePaper/lockscreen-prepared.mov
```

The wallpaper database is:

```text
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
```

LivePaper patches sections such as:

- `Idle`
- `Desktop`
- `Linked`
- per-display sections
- all-spaces display sections

The relevant wallpaper provider is:

```text
com.apple.wallpaper.choice.aerials
```

### 4. Auto Repair

macOS periodically reverts or rewrites wallpaper data. To fight this, LivePaper added an auto-repair system.

The repair command:

```bash
dist/LivePaper.app/Contents/MacOS/LivePaper --repair-lockscreen-aerial
```

The install command:

```bash
dist/LivePaper.app/Contents/MacOS/LivePaper --install-lockscreen-aerial
```

The LaunchAgent path:

```text
~/Library/LaunchAgents/local.livepaper.repair.plist
```

LaunchAgent behavior:

- runs at login
- runs repeatedly
- eventually changed to a short interval, around 10-30 seconds during debugging
- watches important wallpaper paths when possible

The repair agent writes logs to:

```text
~/Library/Application Support/LivePaper/repair-agent.out.log
~/Library/Application Support/LivePaper/repair-agent.err.log
```

### 5. Live Home-Screen Wallpaper

The original app did not actually have the requested home-screen live wallpaper option. This was added later.

The feature includes:

- `Live Home Screen` checkbox
- battery threshold slider
- default battery threshold: 50 percent
- live desktop pauses/hides below the threshold
- live desktop pauses/hides when another app is active

Implementation approach:

- Do not patch the macOS wallpaper database for the home screen.
- Instead, create a borderless desktop-level window using `AVQueuePlayer`.
- Loop the selected video with `AVPlayerLooper`.
- Set the window level to desktop level.
- Ignore mouse events so the wallpaper does not block normal interaction.
- Hide/pause when the frontmost app is not Finder or LivePaper.

This was intentionally separated from the lock-screen workaround so the home-screen live wallpaper can be turned on and off without corrupting macOS wallpaper internals.

## Major Problems Encountered and Fixes

### Problem 1: No Public API for Custom Live Lock-Screen Wallpaper

Initial expectation:

- Select a video file.
- Set it as a live lock-screen wallpaper directly.

Reality:

- macOS does not expose a simple supported API for this.
- Apple Aerial wallpapers are managed through internal wallpaper infrastructure.

Fix:

- Use an existing Apple Aerial asset as a trusted slot.
- Replace the local video file for that Aerial asset.
- Patch `Index.plist` so lock-screen sections point at that asset.

Result:

- It can work, but it is fragile and requires repair logic.

### Problem 2: Custom Manifest Entries Were Rejected

An early attempt involved adding custom `LIVEPAPER_` entries into the Aerial manifest.

Symptoms:

- macOS showed "no wallpaper selected".
- Wallpaper settings became inconsistent.

Fix:

- Stop adding custom manifest entries.
- Remove stale `LIVEPAPER_` manifest/category entries.
- Use an existing Apple asset ID instead.

Lesson:

- Tahoe appears to reject arbitrary custom manifest entries.
- Existing trusted Apple asset IDs are much safer.

### Problem 3: Wallpaper Turned Black

The wallpaper sometimes worked once, then turned black.

Several causes appeared over time:

1. The prepared video was too large or had a format the Wallpaper extension did not like.
2. A passthrough concatenated `.mov` could produce a huge file.
3. A bad export produced a `0B` or duration-zero `.mov`.
4. macOS replaced the custom video with a system video while the database still pointed at the same asset.

Fixes tried:

- Restore the original Apple Aerial backup.
- Replace large passthrough exports with smaller prepared videos.
- Validate the prepared video before copying it into the macOS wallpaper folder.
- Use temporary output files and only move them into place after validation.
- Check that the prepared video has:
  - file size greater than 1 MB
  - duration greater than 1 second
  - a usable video track
  - later, HEVC format when needed

Final important guard:

- Never replace macOS's wallpaper video with an empty or unreadable prepared file.

### Problem 4: Wallpaper Extension Crashed

macOS System Settings showed errors such as:

```text
Settings Error
Extension process `Wallpaper(...)` exited.
```

Likely cause:

- The replacement video file was too large or badly structured.
- One problematic file was around 971 MB and was created from a long stitched passthrough composition.

Fix:

- Avoid very large stitched passthrough exports.
- Use safer prepared outputs.
- Validate output before installing.
- Restart wallpaper-related processes only after a valid repair.

Wallpaper-related processes restarted during debugging:

```text
Wallpaper
WallpaperAgent
WallpaperAerialsExtension
WallpaperImageExtension
WallpaperLegacyExtension
```

### Problem 5: The Static Desktop Did Not Fit the Screen

Symptoms:

- Static image left empty space around the screen.
- It looked like the image was "fit" instead of filled.

Fix:

- Generate still frames using aspect-fill logic.
- Apply the desktop image with a fill-friendly scaling option.

### Problem 6: LivePaper App Would Not Open

After adding home-screen live wallpaper support, LivePaper crashed on launch.

Error:

```text
Fatal error: Use of unimplemented initializer 'init(contentRect:styleMask:backing:defer:)' for class 'LivePaper.DesktopLiveWallpaperWindow'
```

Cause:

- A custom class subclassed `NSWindow`.
- AppKit hit an unsupported initializer path for the subclass.

Fix:

- Do not subclass `NSWindow`.
- Create a plain wrapper object that owns a normal `NSWindow`.

Final pattern:

```swift
final class DesktopLiveWallpaperWindow {
    private let window: NSWindow
    private let player = AVQueuePlayer()
}
```

This fixed the app launch crash.

### Problem 7: macOS Replaced the Wallpaper After a Few Minutes or After Sleep

Symptoms:

- LivePaper wallpaper worked for a short time.
- Then macOS silently reverted to a system wallpaper.
- Sometimes it happened after 5-10 minutes.
- Sometimes it happened after restart.
- Sometimes it happened after sleep/wake.

Findings:

- The wallpaper database often still pointed to LivePaper's chosen asset ID.
- But the actual `.mov` file for that asset was replaced by macOS.

Fixes:

1. Added a LaunchAgent repair process.
2. Added periodic app-level silent repair.
3. Added wake/screen-wake/session-active repair bursts.
4. Stored the chosen lock-screen asset ID in `UserDefaults`.
5. Pinned repairs to the same asset ID instead of following random Aerial slot changes.
6. Added `chflags uchg` to mark the installed `.mov` as user-immutable.

The `uchg` flag was important because macOS could otherwise re-download or overwrite the Aerial video file.

To unlock the file manually if needed:

```bash
chflags nouchg "~/Library/Application Support/com.apple.wallpaper/aerials/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mov"
```

To lock it manually:

```bash
chflags uchg "~/Library/Application Support/com.apple.wallpaper/aerials/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mov"
```

Note: quote expansion with `~` may not work inside quotes in some shells. Prefer `$HOME`:

```bash
chflags nouchg "$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mov"
```

### Problem 8: First Login Screen After Restart Was Static

Observation:

- Lock screen after sleep could be live.
- But after a full restart, the password screen before login could be static.

Reason:

- That first password screen happens before the user LaunchAgent and LivePaper app are running.
- User-level repair logic cannot reliably affect the pre-login boot screen.

Conclusion:

- Sleep/wake lock screen live: achievable.
- First login screen after restart live: not reliable for a normal user-level app.

Possible but not practical:

- privileged system helper
- private Apple entitlements
- deeper system modifications

This was intentionally not pursued further.

### Problem 9: Live Wallpaper Appeared Over Everything After 1-2 Minutes

Symptoms:

- The Mac was set to sleep or display-sleep after about 10 minutes.
- But after only 1-2 minutes of inactivity, the live wallpaper appeared over all apps.
- Moving the mouse or pressing a key dismissed it.
- It looked like LivePaper was forcing sleep early.

Actual cause:

- This was the macOS screen saver idle timer.
- The Aerial/Idle wallpaper slot is used by the screen saver path.
- If the screen saver idle time is too short, macOS shows the live Aerial wallpaper over everything before actual sleep.

Fix:

- Sync the screen saver idle timer with the display sleep timer.
- In the last applied system fix, the idle time was set to:

```text
600 seconds = 10 minutes
```

Command used:

```bash
defaults -currentHost write com.apple.screensaver idleTime -int 600
```

Verification:

```bash
defaults -currentHost read com.apple.screensaver idleTime
pmset -g custom
```

Observed values:

```text
idleTime = 600
displaysleep = 10
```

Important security note:

- Setting screen saver idle time to `0` would disable the idle screen saver trigger.
- That may weaken automatic lock behavior.
- The safer fix was to sync it with the Mac's display sleep timing instead of disabling it.

## Video Preparation Details

Several video preparation methods were tried.

### Passthrough Concatenation

Early method:

- Create an `AVMutableComposition`.
- Repeat the source video until the target duration.
- Export with passthrough.

Problems:

- Could create very large `.mov` files.
- Could contain edit lists or structures the Wallpaper extension disliked.
- Caused crashes/black screen in some cases.

### 1080p Re-Encode

Next method:

- Export a 120-second 1080p `.mov`.
- Strip audio.
- Use a normal H.264 export.

This produced valid movies, but black-screen issues still appeared around sleep/wake in some cases.

### Layered HEVC Writer

Final direction:

- Use HEVC.
- Include temporal-layer metadata.
- Match the kind of behavior Apple's Aerial player expects.

Why:

- Tahoe's Aerial player appears to use temporal information during the transition between live motion and still/slow playback.
- Videos without the right metadata can go black.

Implementation:

- `LayeredHEVCWriter.swift`
- Uses VideoToolbox.
- Creates a 30 fps HEVC output.
- Tags HEVC temporal-level sample attachments.
- Validates output before installation.

## Important Paths

### Project

```text
/Users/anamikarajesh/Desktop/Wallpaper
```

### Built App

```text
/Users/anamikarajesh/Desktop/Wallpaper/dist/LivePaper.app
```

### LivePaper Support Folder

```text
~/Library/Application Support/LivePaper
```

Important files:

```text
~/Library/Application Support/LivePaper/lockscreen-prepared.mov
~/Library/Application Support/LivePaper/repair-agent.out.log
~/Library/Application Support/LivePaper/repair-agent.err.log
```

### macOS Wallpaper Store

```text
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
```

### macOS Aerial Video Folder

```text
~/Library/Application Support/com.apple.wallpaper/aerials/videos
```

Active asset path during final debugging:

```text
~/Library/Application Support/com.apple.wallpaper/aerials/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mov
```

### LaunchAgent

```text
~/Library/LaunchAgents/local.livepaper.repair.plist
```

## Useful Commands

### Build the App

```bash
bash scripts/package_app.sh
```

### Launch the App

```bash
open dist/LivePaper.app
```

### Stop Existing App Process

```bash
killall LivePaper
```

### Install Lock-Screen Wallpaper

```bash
dist/LivePaper.app/Contents/MacOS/LivePaper --install-lockscreen-aerial
```

### Repair Lock-Screen Wallpaper

```bash
dist/LivePaper.app/Contents/MacOS/LivePaper --repair-lockscreen-aerial
```

### Install Repair Agent

```bash
dist/LivePaper.app/Contents/MacOS/LivePaper --install-repair-agent
```

### Uninstall Repair Agent

```bash
dist/LivePaper.app/Contents/MacOS/LivePaper --uninstall-repair-agent
```

### Check LaunchAgent

```bash
launchctl print "gui/$(id -u)/local.livepaper.repair"
```

### Verify App Signature

```bash
codesign --verify --deep --strict dist/LivePaper.app
```

### Check Current Wallpaper Asset ID

```bash
plutil -extract AllSpacesAndDisplays.Idle.Content.Choices.0.Configuration raw "$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist" | base64 --decode | plutil -p -
```

Expected output should include:

```text
assetID => 4C108785-A7BA-422E-9C79-B0129F1D5550
```

### Compare Prepared Video and Installed Aerial Video

```bash
shasum -a 256 \
  "$HOME/Library/Application Support/LivePaper/lockscreen-prepared.mov" \
  "$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mov"
```

The hashes should match.

### Check Immutable Flag

```bash
ls -lO "$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mov"
```

Expected flag:

```text
uchg
```

### Sync Screen Saver Idle Time to 10 Minutes

```bash
defaults -currentHost write com.apple.screensaver idleTime -int 600
```

### Verify Screen Saver Idle Time

```bash
defaults -currentHost read com.apple.screensaver idleTime
```

Expected:

```text
600
```

### Check Display Sleep

```bash
pmset -g custom
```

Look for:

```text
displaysleep 10
```

## Current Known State

As of the latest debugging session:

- The black-screen issue was fixed by ensuring the installed wallpaper video is valid and HEVC-compatible.
- The system wallpaper revert issue was addressed by:
  - pinning the asset ID
  - repairing frequently
  - setting the installed video file as user-immutable with `chflags uchg`
- The unwanted overlay-after-1-minute issue was addressed by setting the screen saver idle time to 10 minutes.
- The first login screen after restart may still be static and is not reliably fixable from a normal user-level app.

## Risks and Caveats

### macOS Updates

This project depends on internal wallpaper storage behavior. A macOS update can break:

- manifest format
- wallpaper store format
- Aerial asset handling
- process names
- timing of wallpaper repair
- file replacement behavior

The app can be updated after macOS updates, but there is no guarantee that the workaround will keep working forever.

### User-Immutable File Flag

The final fix uses:

```bash
chflags uchg
```

This prevents macOS from casually replacing the `.mov` file.

However:

- It may block macOS from updating that Aerial asset.
- The app must unlock the file before replacing it.
- If cleanup is needed, remove the flag manually with `chflags nouchg`.

### Screen Saver and Security

The screen saver idle timer affects when macOS starts the idle screen saver.

It should not be blindly disabled unless the user accepts the security tradeoff. The safer fix is to sync it with the display sleep time.

### App Store Distribution

This is not App Store-friendly behavior because it relies on private/internal macOS wallpaper storage. For GitHub, describe it as an experimental personal utility.

## Suggested GitHub README Warning

Use wording like this near the top of the repository:

```markdown
Warning: LivePaper uses macOS wallpaper internals to support custom live lock-screen video. This is an experimental personal utility, not an officially supported macOS wallpaper API. It may break after macOS updates and should be used only if you are comfortable restoring wallpaper settings manually.
```

## Suggested Future Improvements

1. Add a "Restore Original Apple Wallpaper" button.
2. Save backups in a clearer LivePaper-managed folder.
3. Add a diagnostics panel showing:
   - active asset ID
   - prepared video validity
   - hash match status
   - immutable flag status
   - LaunchAgent status
   - screen saver idle time
4. Add a setting to sync screen saver idle time with display sleep automatically.
5. Add a cleanup/uninstall command that:
   - disables LaunchAgent
   - removes `uchg`
   - restores the original Aerial video backup
   - restores previous wallpaper database backup
6. Avoid patching `Desktop` wallpaper sections unless the user chooses to link desktop and lock-screen behavior.
7. Use modern async AVFoundation APIs instead of deprecated synchronous properties.
8. Add better logging around every repair decision.
9. Add unit tests for plist patching and asset ID detection.
10. Add a visible "unsupported macOS internals" disclaimer in the settings window.

## Recommended Handoff Prompt for Another AI or Developer

```text
This is a macOS Swift app called LivePaper. It attempts to provide custom live lock-screen wallpaper by replacing a local Apple Aerial wallpaper video and patching the user's com.apple.wallpaper Store/Index.plist. The approach is experimental and depends on macOS wallpaper internals.

The most important bugs already encountered were:
- custom manifest entries were rejected
- System Settings wallpaper extension crashed from huge or invalid MOV files
- lock screen went black after sleep due to bad/unsupported video format
- macOS silently replaced the custom Aerial MOV after a delay
- the app crashed when subclassing NSWindow for the desktop live wallpaper
- the Aerial screen saver appeared over apps after 1-2 minutes because com.apple.screensaver idleTime was too low

Important fixes:
- use an existing trusted Apple Aerial asset ID instead of adding custom manifest entries
- validate prepared videos before copying them into the wallpaper folder
- use temp output files before replacing the active MOV
- use a repair LaunchAgent
- remember/pin the selected lock-screen asset ID
- mark the installed MOV as user-immutable with chflags uchg
- implement the optional live desktop wallpaper as a normal desktop-level AVPlayer window, not by patching macOS wallpaper internals
- sync screen saver idleTime with display sleep to stop the live wallpaper overlay from appearing too early

Be careful: do not delete or replace the active Aerial MOV without removing uchg first. Do not use git reset or destructive cleanup without checking user backups.
```

