@preconcurrency import AVFoundation
import Foundation
import VideoToolbox

// Tahoe's Aerial player slows the video to a still when the screen unlocks. That ramp reads
// each frame's HEVC temporal level and fails ("noTemporalInfo", black desktop) on any video
// without one, so the wallpaper must be HEVC with a 15 fps base layer under a 30 fps layer,
// the same layout as the two lowest levels of Apple's own aerials.
final class LayeredHEVCWriter: @unchecked Sendable {
    enum WriterError: LocalizedError {
        case encoderUnavailable(OSStatus)
        case noVideoTrack
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .encoderUnavailable(let status):
                return "the layered HEVC encoder is unavailable (\(status))."
            case .noVideoTrack:
                return "the video has no video track."
            case .encodeFailed(let reason):
                return reason
            }
        }
    }

    private static let frameRate: Int32 = 30
    private static let maxSize = CGSize(width: 1920, height: 1080)
    private static let bitRate = 12_000_000

    private let lock = NSLock()
    private var failure: String?

    func write(asset: AVAsset, duration: CMTime, to destinationURL: URL) throws {
        guard let track = asset.tracks(withMediaType: .video).first else { throw WriterError.noVideoTrack }

        let composition = AVMutableVideoComposition(propertiesOf: asset)
        let size = Self.encodedSize(for: composition.renderSize)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        output.videoComposition = composition
        reader.add(output)

        nonisolated(unsafe) let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = true
        nonisolated(unsafe) let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        let session = try makeSession(size: size)
        defer { VTCompressionSessionInvalidate(session) }

        guard reader.startReading() else {
            throw WriterError.encodeFailed(reader.error?.localizedDescription ?? "could not read the video.")
        }
        guard writer.startWriting() else {
            throw WriterError.encodeFailed(writer.error?.localizedDescription ?? "could not write the video.")
        }
        writer.startSession(atSourceTime: .zero)

        // Emit a constant 30 fps, holding the latest source frame, so levels 0 and 1 are
        // exactly 15 and 30 fps whatever the source frame rate is.
        let frameDuration = CMTime(value: 1, timescale: Self.frameRate)
        let frameCount = Int64(duration.seconds * Double(Self.frameRate))
        var heldFrame: CVImageBuffer?
        var upcoming = output.copyNextSampleBuffer()

        for index in 0..<frameCount {
            let time = CMTime(value: index, timescale: Self.frameRate)
            while let next = upcoming, CMSampleBufferGetPresentationTimeStamp(next) <= time {
                heldFrame = CMSampleBufferGetImageBuffer(next) ?? heldFrame
                upcoming = output.copyNextSampleBuffer()
            }
            guard let frame = heldFrame, currentFailure() == nil else { break }

            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: frame,
                presentationTimeStamp: time,
                duration: frameDuration,
                frameProperties: nil,
                infoFlagsOut: nil
            ) { [self] status, _, sampleBuffer in
                append(sampleBuffer, status: status, to: input, writer: writer)
            }
            if status != noErr { fail("encoding failed (\(status)).") }
        }

        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        input.markAsFinished()

        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()

        if let failure = currentFailure() { throw WriterError.encodeFailed(failure) }
        guard reader.status != .failed else {
            throw WriterError.encodeFailed(reader.error?.localizedDescription ?? "could not read the video.")
        }
        guard writer.status == .completed else {
            throw WriterError.encodeFailed(writer.error?.localizedDescription ?? "could not write the video.")
        }
    }

    private func makeSession(size: CGSize) throws -> VTCompressionSession {
        // Only the low-latency HEVC encoder produces temporal layers.
        let specification = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue] as CFDictionary
        var created: VTCompressionSession?
        var status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(size.width),
            height: Int32(size.height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &created
        )
        guard status == noErr, let session = created else { throw WriterError.encoderUnavailable(status) }

        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_BaseLayerFrameRateFraction, value: 0.5 as CFNumber)
        guard status == noErr else {
            VTCompressionSessionInvalidate(session)
            throw WriterError.encoderUnavailable(status)
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: Self.bitRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: Self.frameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: Self.frameRate as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }

    private func append(_ sampleBuffer: CMSampleBuffer?, status: OSStatus, to input: AVAssetWriterInput, writer: AVAssetWriter) {
        guard status == noErr, let sampleBuffer else {
            fail("encoding failed (\(status)).")
            return
        }
        guard Self.tagTemporalLevel(sampleBuffer) else {
            fail("the encoder did not produce temporal layers.")
            return
        }

        lock.lock()
        defer { lock.unlock() }
        guard failure == nil else { return }
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { break }
            usleep(1_000)
        }
        if !input.append(sampleBuffer) {
            failure = writer.error?.localizedDescription ?? "could not write the video."
        }
    }

    // The encoder marks temporal layers only inside the bitstream. The player reads them from
    // per-sample attachments, which the movie writer stores when they are set here.
    private static func tagTemporalLevel(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let data = CMSampleBufferGetDataBuffer(sampleBuffer),
              let atoms = CMFormatDescriptionGetExtension(
                  format,
                  extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
              ) as? [String: Any],
              let hvcC = atoms["hvcC"] as? Data, hvcC.count >= 13,
              sampleBuffer.sampleAttachments.count > 0 else { return false }

        // 4-byte NAL length, then the 2-byte NAL header holding the type and temporal ID.
        var header = [UInt8](repeating: 0, count: 6)
        guard CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: header.count, destination: &header) == kCMBlockBufferNoErr else {
            return false
        }
        let nalType = (header[4] >> 1) & 0x3f
        let temporalLevel = Int(header[5] & 0x07) - 1
        guard temporalLevel >= 0 else { return false }

        let bytes = [UInt8](hvcC)
        let info: [CFString: Any] = [
            kCMHEVCTemporalLevelInfoKey_TemporalLevel: temporalLevel,
            kCMHEVCTemporalLevelInfoKey_ProfileSpace: Int(bytes[1] >> 6),
            kCMHEVCTemporalLevelInfoKey_TierFlag: Int((bytes[1] >> 5) & 1),
            kCMHEVCTemporalLevelInfoKey_ProfileIndex: Int(bytes[1] & 0x1f),
            kCMHEVCTemporalLevelInfoKey_ProfileCompatibilityFlags: Data(bytes[2..<6]),
            kCMHEVCTemporalLevelInfoKey_ConstraintIndicatorFlags: Data(bytes[6..<12]),
            kCMHEVCTemporalLevelInfoKey_LevelIndex: Int(bytes[12])
        ]
        sampleBuffer.sampleAttachments[0][.hevcTemporalLevelInfo] = info as CFDictionary
        // NAL types 2 and 3 are temporal sub-layer access pictures.
        if nalType == 2 || nalType == 3 {
            sampleBuffer.sampleAttachments[0][.hevcTemporalSubLayerAccess] = kCFBooleanTrue
        }
        return true
    }

    private static func encodedSize(for size: CGSize) -> CGSize {
        let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
        func even(_ value: CGFloat) -> CGFloat { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    private func fail(_ reason: String) {
        lock.lock()
        if failure == nil { failure = reason }
        lock.unlock()
    }

    private func currentFailure() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }
}
