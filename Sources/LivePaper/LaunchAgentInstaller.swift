import Foundation

@MainActor
final class LaunchAgentInstaller {
    private let fileManager = FileManager.default
    private let label = "local.livepaper.repair"

    private var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    func install(settings: SettingsStore) throws {
        let supportDirectory = settings.supportDirectory
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let launchAgentsDirectory = plistURL.deletingLastPathComponent()
        let wallpaperRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper", isDirectory: true)
        let storeURL = wallpaperRoot.appendingPathComponent("Store/Index.plist")
        var watchPaths = [storeURL.path]
        if let assetID = settings.lockScreenAssetID {
            watchPaths.append(wallpaperRoot.appendingPathComponent("aerials/videos/\(assetID).mov").path)
        }
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                executableURL.path,
                "--repair-lockscreen-aerial"
            ],
            "RunAtLoad": true,
            "StartInterval": 10,
            "WatchPaths": watchPaths,
            "StandardOutPath": supportDirectory.appendingPathComponent("repair-agent.out.log").path,
            "StandardErrorPath": supportDirectory.appendingPathComponent("repair-agent.err.log").path
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        reload()
    }

    func uninstall() throws {
        bootout()
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
    }

    private func reload() {
        bootout()
        runLaunchctl(arguments: ["bootstrap", domain, plistURL.path])
        runLaunchctl(arguments: ["kickstart", "-k", "\(domain)/\(label)"])
    }

    private func bootout() {
        runLaunchctl(arguments: ["bootout", domain, plistURL.path])
        runLaunchctl(arguments: ["bootout", "\(domain)/\(label)"])
    }

    private var domain: String {
        "gui/\(getuid())"
    }

    private func runLaunchctl(arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
