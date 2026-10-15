import AppKit

enum LivePaperError: LocalizedError {
    case missingVideo
    case missingScreens
    case unreadableVideo(URL)

    var errorDescription: String? {
        switch self {
        case .missingVideo:
            return "Choose a video first."
        case .missingScreens:
            return "No displays were found."
        case .unreadableVideo(let url):
            return "Could not read video: \(url.lastPathComponent)"
        }
    }
}

@MainActor
final class WallpaperController {
    func generateAndApplyStaticFrame(settings: SettingsStore) throws {
        guard let videoURL = settings.selectedVideoURL else { throw LivePaperError.missingVideo }
        guard FileManager.default.fileExists(atPath: videoURL.path) else { throw LivePaperError.unreadableVideo(videoURL) }
        guard !NSScreen.screens.isEmpty else { throw LivePaperError.missingScreens }

        for screen in NSScreen.screens {
            let imageURL = settings.staticWallpaperURL(for: screen)
            try FrameExtractor.writeAspectFillJPEGFrame(
                from: videoURL,
                atSeconds: settings.selectedFrameTime,
                targetPixelSize: screen.pixelSize,
                to: imageURL
            )
            try NSWorkspace.shared.setDesktopImageURL(
                imageURL,
                for: screen,
                options: [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue]
            )
        }
    }
}

private extension NSScreen {
    var pixelSize: CGSize {
        CGSize(width: frame.width * backingScaleFactor, height: frame.height * backingScaleFactor)
    }
}
