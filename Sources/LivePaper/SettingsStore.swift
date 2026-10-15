import AppKit
import Foundation

@MainActor
final class SettingsStore: NSObject {
    static let shared = SettingsStore()
    static let didChangeNotification = Notification.Name("LivePaperSettingsDidChange")

    private enum Key {
        static let selectedVideoPath = "selectedVideoPath"
        static let selectedFrameTime = "selectedFrameTime"
        static let batteryThreshold = "batteryThreshold"
        static let liveDesktopAllowed = "liveDesktopAllowed"
        static let lockScreenAssetID = "lockScreenAssetID"
    }

    private let defaults = UserDefaults.standard

    @objc dynamic var selectedVideoPath: String? {
        didSet {
            defaults.set(selectedVideoPath, forKey: Key.selectedVideoPath)
            notifyChanged()
        }
    }

    @objc dynamic var selectedFrameTime: Double {
        didSet {
            defaults.set(selectedFrameTime, forKey: Key.selectedFrameTime)
            notifyChanged()
        }
    }

    @objc dynamic var batteryThreshold: Int {
        didSet {
            defaults.set(batteryThreshold, forKey: Key.batteryThreshold)
            notifyChanged()
        }
    }

    @objc dynamic var liveDesktopAllowed: Bool {
        didSet {
            defaults.set(liveDesktopAllowed, forKey: Key.liveDesktopAllowed)
            notifyChanged()
        }
    }

    @objc dynamic var lockScreenAssetID: String? {
        didSet {
            defaults.set(lockScreenAssetID, forKey: Key.lockScreenAssetID)
            notifyChanged()
        }
    }

    @objc dynamic var statusMessage: String = "Choose a video, then install live lock screen."

    var selectedVideoURL: URL? {
        guard let selectedVideoPath else { return nil }
        return URL(fileURLWithPath: selectedVideoPath)
    }

    var supportDirectory: URL {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LivePaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func staticWallpaperURL(for screen: NSScreen) -> URL {
        supportDirectory.appendingPathComponent("static-\(screen.displayID).jpg")
    }

    private override init() {
        selectedVideoPath = defaults.string(forKey: Key.selectedVideoPath)
        selectedFrameTime = defaults.object(forKey: Key.selectedFrameTime) as? Double ?? 0
        batteryThreshold = defaults.object(forKey: Key.batteryThreshold) as? Int ?? 50
        liveDesktopAllowed = defaults.bool(forKey: Key.liveDesktopAllowed)
        lockScreenAssetID = defaults.string(forKey: Key.lockScreenAssetID)
        super.init()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
