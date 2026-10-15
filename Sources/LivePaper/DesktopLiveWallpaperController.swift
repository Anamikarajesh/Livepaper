import AppKit
import AVFoundation
import IOKit.ps

@MainActor
final class DesktopLiveWallpaperController {
    private let settings: SettingsStore
    private var windows: [DesktopLiveWallpaperWindow] = []
    private var timer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    private var frontmostBundleIdentifier: String?
    private var activeVideoURL: URL?

    init(settings: SettingsStore) {
        self.settings = settings
        frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func start() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: SettingsStore.didChangeNotification,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindowsIfNeeded() }
        }

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.frontmostBundleIdentifier = app?.bundleIdentifier
                self?.updatePlaybackState()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePlaybackState() }
        }

        update()
    }

    func stop() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
        }
        timer?.invalidate()
        settingsObserver = nil
        screenObserver = nil
        appObserver = nil
        timer = nil
        closeWindows()
    }

    private func update() {
        guard settings.liveDesktopAllowed, let videoURL = settings.selectedVideoURL else {
            closeWindows()
            return
        }

        if activeVideoURL != videoURL || windows.count != NSScreen.screens.count {
            closeWindows()
            activeVideoURL = videoURL
            windows = NSScreen.screens.map { DesktopLiveWallpaperWindow(screen: $0, videoURL: videoURL) }
        }

        updatePlaybackState()
    }

    private func rebuildWindowsIfNeeded() {
        guard settings.liveDesktopAllowed else { return }
        let videoURL = activeVideoURL
        closeWindows()
        activeVideoURL = nil
        if videoURL != nil {
            update()
        }
    }

    private func updatePlaybackState() {
        guard settings.liveDesktopAllowed, !windows.isEmpty else { return }

        let shouldPlay = batteryIsAboveThreshold && frontmostAppAllowsLiveDesktop
        for window in windows {
            if shouldPlay {
                window.showAndPlay()
            } else {
                window.pauseAndHide()
            }
        }
    }

    private var batteryIsAboveThreshold: Bool {
        guard let percentage = BatteryReader.currentPercentage() else { return true }
        return percentage >= settings.batteryThreshold
    }

    private var frontmostAppAllowsLiveDesktop: Bool {
        guard let frontmostBundleIdentifier else { return true }
        return frontmostBundleIdentifier == "com.apple.finder"
            || frontmostBundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func closeWindows() {
        windows.forEach { $0.closeWallpaper() }
        windows = []
        activeVideoURL = nil
    }
}

@MainActor
private final class DesktopLiveWallpaperWindow {
    private let window: NSWindow
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(screen: NSScreen, videoURL: URL) {
        let content = PlayerView(player: player)
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.contentView = content
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)

        let item = AVPlayerItem(url: videoURL)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
    }

    func showAndPlay() {
        window.orderFrontRegardless()
        player.play()
    }

    func pauseAndHide() {
        player.pause()
        window.orderOut(nil)
    }

    func closeWallpaper() {
        player.pause()
        window.close()
    }
}

private final class PlayerView: NSView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private enum BatteryReader {
    static func currentPercentage() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0 else {
                continue
            }
            return Int((Double(current) / Double(maximum) * 100).rounded())
        }

        return nil
    }
}
