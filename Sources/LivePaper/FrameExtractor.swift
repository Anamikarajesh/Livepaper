import AppKit
import AVFoundation

enum FrameExtractor {
    static func duration(of videoURL: URL) async -> Double {
        let asset = AVURLAsset(url: videoURL)
        let duration = try? await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration ?? .zero)
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    static func image(from videoURL: URL, atSeconds seconds: Double, maximumSize: CGSize) throws -> NSImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func writeAspectFillJPEGFrame(from videoURL: URL, atSeconds seconds: Double, targetPixelSize: CGSize, to outputURL: URL) throws {
        let source = try cgImage(from: videoURL, atSeconds: seconds)
        let width = max(Int(targetPixelSize.width.rounded()), 1)
        let height = max(Int(targetPixelSize.height.rounded()), 1)
        let outputAspect = CGFloat(width) / CGFloat(height)
        let sourceAspect = CGFloat(source.width) / CGFloat(source.height)

        let cropRect: CGRect
        if sourceAspect > outputAspect {
            let cropWidth = CGFloat(source.height) * outputAspect
            cropRect = CGRect(x: (CGFloat(source.width) - cropWidth) / 2, y: 0, width: cropWidth, height: CGFloat(source.height))
        } else {
            let cropHeight = CGFloat(source.width) / outputAspect
            cropRect = CGRect(x: 0, y: (CGFloat(source.height) - cropHeight) / 2, width: CGFloat(source.width), height: cropHeight)
        }

        guard let cropped = source.cropping(to: cropRect.integral),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw LivePaperError.unreadableVideo(videoURL)
        }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.94]) else {
            throw LivePaperError.unreadableVideo(videoURL)
        }

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: outputURL, options: .atomic)
    }

    private static func cgImage(from videoURL: URL, atSeconds seconds: Double) throws -> CGImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(at: CMTime(seconds: max(seconds, 0), preferredTimescale: 600), actualTime: nil)
    }
}
