import AppKit
import AVFoundation
import Foundation

@MainActor
final class AerialWallpaperInstaller {
    private let fileManager = FileManager.default
    private let replacementDuration = CMTime(seconds: 120, preferredTimescale: 600)

    private struct InstallationContext {
        let manifestURL: URL
        let storeURL: URL
        let replacementAssetID: String
        let replacementVideoURL: URL
        let preparedVideoURL: URL
    }

    enum InstallerError: LocalizedError {
        case missingVideo
        case unreadableVideo(URL)
        case exportFailed(String)
        case invalidManifest
        case invalidWallpaperStore

        var errorDescription: String? {
            switch self {
            case .missingVideo:
                return "Choose a video before installing a live lock-screen wallpaper."
            case .unreadableVideo(let url):
                return "Could not read video: \(url.lastPathComponent)"
            case .exportFailed(let reason):
                return "Could not prepare video for macOS wallpaper engine: \(reason)"
            case .invalidManifest:
                return "Could not read the Aerial wallpaper manifest."
            case .invalidWallpaperStore:
                return "Could not read the wallpaper store."
            }
        }
    }

    func installSelectedVideo(settings: SettingsStore) throws {
        guard let sourceVideoURL = settings.selectedVideoURL else { throw InstallerError.missingVideo }
        guard fileManager.fileExists(atPath: sourceVideoURL.path) else { throw InstallerError.unreadableVideo(sourceVideoURL) }

        let context = try installationContext(settings: settings)
        try backUp(urls: [context.storeURL, context.replacementVideoURL])
        try removeStaleCustomEntries(manifestURL: context.manifestURL)
        try prepareVideo(sourceURL: sourceVideoURL, destinationURL: context.preparedVideoURL)
        try applyPreparedVideo(context: context)
        settings.lockScreenAssetID = context.replacementAssetID
    }

    func repairSelectedVideo(settings: SettingsStore) throws -> Bool {
        guard let sourceVideoURL = settings.selectedVideoURL else { throw InstallerError.missingVideo }
        guard fileManager.fileExists(atPath: sourceVideoURL.path) else { throw InstallerError.unreadableVideo(sourceVideoURL) }

        let context = try installationContext(settings: settings)
        if !preparedVideoIsUsable(context.preparedVideoURL) {
            try prepareVideo(sourceURL: sourceVideoURL, destinationURL: context.preparedVideoURL)
        }
        let repaired = try applyPreparedVideo(context: context)
        settings.lockScreenAssetID = context.replacementAssetID
        return repaired
    }

    private func installationContext(settings: SettingsStore) throws -> InstallationContext {
        let root = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper", isDirectory: true)
        let aerials = root.appendingPathComponent("aerials", isDirectory: true)
        let manifestURL = aerials.appendingPathComponent("manifest/entries.json")
        let storeURL = root.appendingPathComponent("Store/Index.plist")
        let replacement = try trustedLocalAerialAsset(
            aerialsDirectory: aerials,
            manifestURL: manifestURL,
            preferredAssetID: settings.lockScreenAssetID
        )
        let preparedVideoURL = settings.supportDirectory.appendingPathComponent("lockscreen-prepared.mov")

        return InstallationContext(
            manifestURL: manifestURL,
            storeURL: storeURL,
            replacementAssetID: replacement.assetID,
            replacementVideoURL: replacement.videoURL,
            preparedVideoURL: preparedVideoURL
        )
    }

    @discardableResult
    private func applyPreparedVideo(context: InstallationContext) throws -> Bool {
        var repaired = false
        guard preparedVideoIsUsable(context.preparedVideoURL) else {
            throw InstallerError.exportFailed("prepared wallpaper video is empty or unreadable.")
        }

        if !fileManager.contentsEqual(atPath: context.preparedVideoURL.path, andPath: context.replacementVideoURL.path) {
            if fileManager.fileExists(atPath: context.replacementVideoURL.path) {
                setUserImmutable(false, for: context.replacementVideoURL)
                try fileManager.removeItem(at: context.replacementVideoURL)
            }
            try fileManager.copyItem(at: context.preparedVideoURL, to: context.replacementVideoURL)
            setUserImmutable(true, for: context.replacementVideoURL)
            repaired = true
        } else {
            setUserImmutable(true, for: context.replacementVideoURL)
        }

        if try !wallpaperStoreUsesAsset(storeURL: context.storeURL, assetID: context.replacementAssetID) {
            try patchWallpaperStore(storeURL: context.storeURL, assetID: context.replacementAssetID)
            repaired = true
        }

        if repaired {
            restartWallpaperServices()
        }
        return repaired
    }

    private func backUp(urls: [URL]) throws {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for url in urls where fileManager.fileExists(atPath: url.path) {
            let backupURL = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).livepaper-backup-\(stamp)")
            try fileManager.copyItem(at: url, to: backupURL)
        }
    }

    private func prepareVideo(sourceURL: URL, destinationURL: URL) throws {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp.mov")
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
            throw InstallerError.unreadableVideo(sourceURL)
        }
        guard asset.duration.seconds.isFinite, asset.duration > .zero else {
            throw InstallerError.unreadableVideo(sourceURL)
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw InstallerError.exportFailed("passthrough export is unavailable.")
        }

        var insertionTime = CMTime.zero
        let sourceDuration = asset.duration
        while insertionTime < replacementDuration {
            let remaining = replacementDuration - insertionTime
            let segmentDuration = min(sourceDuration, remaining)
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: segmentDuration),
                of: sourceVideoTrack,
                at: insertionTime
            )
            insertionTime = insertionTime + segmentDuration
        }
        videoTrack.preferredTransform = sourceVideoTrack.preferredTransform

        do {
            try LayeredHEVCWriter().write(asset: composition, duration: replacementDuration, to: temporaryURL)
        } catch {
            throw InstallerError.exportFailed(error.localizedDescription)
        }
        guard preparedVideoIsUsable(temporaryURL) else {
            throw InstallerError.exportFailed("exported wallpaper video is empty or unreadable.")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private func preparedVideoIsUsable(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 1_000_000 else {
            return false
        }

        let asset = AVURLAsset(url: url)
        return asset.duration.seconds.isFinite
            && asset.duration.seconds > 1
            && asset.tracks(withMediaType: .video).contains { track in
                track.formatDescriptions.contains { description in
                    let format = description as! CMFormatDescription
                    return CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC
                }
            }
    }

    private func setUserImmutable(_ locked: Bool, for url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = [locked ? "uchg" : "nouchg", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func trustedLocalAerialAsset(aerialsDirectory: URL, manifestURL: URL, preferredAssetID: String?) throws -> (assetID: String, videoURL: URL) {
        let data = try Data(contentsOf: manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = manifest["assets"] as? [[String: Any]] else {
            throw InstallerError.invalidManifest
        }

        let videosDirectory = aerialsDirectory.appendingPathComponent("videos", isDirectory: true)
        let localIDs = Set((try? fileManager.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "mov" }
            .map { $0.deletingPathExtension().lastPathComponent.uppercased() } ?? [])

        if let preferredAssetID = preferredAssetID?.uppercased(), localIDs.contains(preferredAssetID) {
            return (preferredAssetID, videosDirectory.appendingPathComponent("\(preferredAssetID).mov"))
        }

        for asset in assets {
            let shotID = asset["shotID"] as? String ?? ""
            guard !shotID.hasPrefix("LIVEPAPER_"),
                  let id = (asset["id"] as? String)?.uppercased(),
                  localIDs.contains(id) else { continue }
            return (id, videosDirectory.appendingPathComponent("\(id).mov"))
        }

        throw InstallerError.invalidManifest
    }

    // Earlier builds added LIVEPAPER_ entries to the manifest. Tahoe rejects them, so a
    // wallpaper section that still selects one shows no wallpaper at all.
    private func removeStaleCustomEntries(manifestURL: URL) throws {
        let data = try Data(contentsOf: manifestURL)
        guard var manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = manifest["assets"] as? [[String: Any]] else {
            throw InstallerError.invalidManifest
        }

        let categories = manifest["categories"] as? [[String: Any]] ?? []
        let keptAssets = assets.filter { !(($0["shotID"] as? String) ?? "").hasPrefix("LIVEPAPER_") }
        let keptCategories = categories.filter { !(($0["id"] as? String) ?? "").hasPrefix("LIVEPAPER-") }
        guard keptAssets.count != assets.count || keptCategories.count != categories.count else { return }

        try backUp(urls: [manifestURL])
        manifest["assets"] = keptAssets
        if manifest["categories"] != nil {
            manifest["categories"] = keptCategories
        }
        let output = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try output.write(to: manifestURL, options: .atomic)
    }

    private func patchWallpaperStore(storeURL: URL, assetID: String) throws {
        let data = try Data(contentsOf: storeURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw InstallerError.invalidWallpaperStore
        }

        patchWallpaperNodes(plist, assetID: assetID, date: Date())

        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try output.write(to: storeURL, options: .atomic)
    }

    private func wallpaperStoreUsesAsset(storeURL: URL, assetID: String) throws -> Bool {
        let data = try Data(contentsOf: storeURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary else {
            throw InstallerError.invalidWallpaperStore
        }
        var checkedSections = 0
        var mismatchedSections = 0
        inspectWallpaperNodes(plist, assetID: assetID, checkedSections: &checkedSections, mismatchedSections: &mismatchedSections)
        return checkedSections > 0 && mismatchedSections == 0
    }

    private func inspectWallpaperNodes(_ node: NSDictionary, assetID: String, checkedSections: inout Int, mismatchedSections: inout Int) {
        let sectionKeys = ["Idle", "Desktop", "Linked"]
        for key in sectionKeys {
            guard let section = node[key] as? NSDictionary else { continue }
            checkedSections += 1
            if selectedAssetID(in: section) != assetID {
                mismatchedSections += 1
            }
        }

        for key in node.allKeys {
            if let name = key as? String, sectionKeys.contains(name) { continue }
            if let child = node[key] as? NSDictionary {
                inspectWallpaperNodes(child, assetID: assetID, checkedSections: &checkedSections, mismatchedSections: &mismatchedSections)
            }
        }
    }

    private func selectedAssetID(in section: NSDictionary) -> String? {
        guard let content = section["Content"] as? NSDictionary,
              let choices = content["Choices"] as? [NSDictionary],
              let configuration = choices.first?["Configuration"] as? Data,
              let decoded = try? PropertyListSerialization.propertyList(from: configuration, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return decoded["assetID"] as? String
    }

    // Desktop must point at the same trusted asset as Idle. Left alone it can keep
    // referencing an asset Tahoe no longer accepts, which renders black after unlock.
    private func patchWallpaperNodes(_ node: NSMutableDictionary, assetID: String, date: Date) {
        let sectionKeys = ["Idle", "Desktop", "Linked"]
        for key in sectionKeys where node[key] is NSDictionary {
            node[key] = wallpaperSection(assetID: assetID, date: date)
        }

        for key in node.allKeys {
            if let name = key as? String, sectionKeys.contains(name) { continue }
            if let child = node[key] as? NSMutableDictionary {
                patchWallpaperNodes(child, assetID: assetID, date: date)
            } else if let child = node[key] as? NSDictionary {
                let mutable = child.mutableCopy() as! NSMutableDictionary
                patchWallpaperNodes(mutable, assetID: assetID, date: date)
                node[key] = mutable
            }
        }
    }

    private func wallpaperSection(assetID: String, date: Date) -> NSMutableDictionary {
        [
            "Content": [
                "Choices": [[
                    "Configuration": binaryPlist(["assetID": assetID]),
                    "Files": [],
                    "Provider": "com.apple.wallpaper.choice.aerials"
                ]],
                "EncodedOptionValues": binaryPlist(["values": [:]]),
                "Shuffle": "$null"
            ],
            "LastSet": date,
            "LastUse": date
        ]
    }

    private func binaryPlist(_ value: [String: Any]) -> Data {
        (try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)) ?? Data()
    }

    private func restartWallpaperServices() {
        for name in ["Wallpaper", "WallpaperAgent", "WallpaperAerialsExtension", "WallpaperImageExtension", "WallpaperLegacyExtension"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [name]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
