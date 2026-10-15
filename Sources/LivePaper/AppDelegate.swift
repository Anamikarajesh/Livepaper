import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = SettingsStore.shared
    private let wallpaperController = WallpaperController()
    private let aerialInstaller = AerialWallpaperInstaller()
    private lazy var desktopLiveController = DesktopLiveWallpaperController(settings: settings)
    private var settingsWindowController: SettingsWindowController?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var repairTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "LivePaper"
        desktopLiveController.start()
        startWallpaperRepairObservers()

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Install Live Lock Screen", action: #selector(installLiveLockScreen), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Repair Lock Screen Now", action: #selector(repairLiveLockScreen), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Apply Static Desktop", action: #selector(applyStaticDesktop), keyEquivalent: "a"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Enable Auto Repair", action: #selector(enableAutoRepair), keyEquivalent: "e"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LivePaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    @objc private func installLiveLockScreen() {
        do {
            try aerialInstaller.installSelectedVideo(settings: settings)
            try LaunchAgentInstaller().install(settings: settings)
            settings.statusMessage = "Installed live lock-screen wallpaper and auto repair."
        } catch {
            settings.statusMessage = error.localizedDescription
        }
    }

    @objc private func repairLiveLockScreen() {
        do {
            let repaired = try aerialInstaller.repairSelectedVideo(settings: settings)
            settings.statusMessage = repaired ? "Repaired live lock-screen wallpaper." : "Live lock-screen wallpaper is already installed."
        } catch {
            settings.statusMessage = error.localizedDescription
        }
    }

    @objc private func enableAutoRepair() {
        do {
            try LaunchAgentInstaller().install(settings: settings)
            settings.statusMessage = "Enabled LivePaper auto repair."
        } catch {
            settings.statusMessage = error.localizedDescription
        }
    }

    @objc private func applyStaticDesktop() {
        do {
            try wallpaperController.generateAndApplyStaticFrame(settings: settings)
            settings.statusMessage = "Applied static desktop wallpaper."
        } catch {
            settings.statusMessage = error.localizedDescription
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopWallpaperRepairObservers()
        desktopLiveController.stop()
    }

    private func startWallpaperRepairObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]

        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleWakeRepairBurst() }
            }
        }

        repairTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.repairLiveLockScreenSilently() }
        }
        repairLiveLockScreenSilently()
    }

    private func stopWallpaperRepairObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers = []
        repairTimer?.invalidate()
        repairTimer = nil
    }

    private func repairLiveLockScreenSilently() {
        guard settings.selectedVideoURL != nil else { return }
        do {
            _ = try aerialInstaller.repairSelectedVideo(settings: settings)
        } catch {
            settings.statusMessage = error.localizedDescription
        }
    }

    private func scheduleWakeRepairBurst() {
        for delay in [0.25, 1.5, 4.0, 8.0, 15.0] {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.repairLiveLockScreenSilently() }
            }
        }
    }
}
