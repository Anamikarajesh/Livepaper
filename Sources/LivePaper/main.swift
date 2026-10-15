import AppKit

if CommandLine.arguments.contains("--install-lockscreen-aerial") {
    do {
        try AerialWallpaperInstaller().installSelectedVideo(settings: SettingsStore.shared)
        try LaunchAgentInstaller().install(settings: SettingsStore.shared)
        print("Installed live lock-screen wallpaper.")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if CommandLine.arguments.contains("--apply-static") {
    do {
        try WallpaperController().generateAndApplyStaticFrame(settings: SettingsStore.shared)
        print("Applied static desktop wallpaper.")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if CommandLine.arguments.contains("--repair-lockscreen-aerial") {
    do {
        let repaired = try AerialWallpaperInstaller().repairSelectedVideo(settings: SettingsStore.shared)
        if repaired {
            print("Repaired live lock-screen wallpaper.")
        }
        exit(EXIT_SUCCESS)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if CommandLine.arguments.contains("--install-repair-agent") {
    do {
        try LaunchAgentInstaller().install(settings: SettingsStore.shared)
        print("Installed LivePaper auto repair.")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if CommandLine.arguments.contains("--uninstall-repair-agent") {
    do {
        try LaunchAgentInstaller().uninstall()
        print("Uninstalled LivePaper auto repair.")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
