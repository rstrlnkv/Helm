import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

/// **The layer that keeps a mask out of screenshots.** It is an `AVSampleBufferDisplayLayer` with
/// `preventsCapture` on, showing one opaque frame, used as the mask of the mask's shape. The mechanism's intent,
/// as the standalone app observed it, is that the compositor on screen draws the opaque frame and a capture
/// leaves the protected frame out and so sees the desktop under the corner; that is not measured here. `sharingType` of the window is left at its default, so the window list the engine samples
/// reads the window as any other.
///
/// Carried over from the standalone app without the macOS 14 branches. The one shared 16 × 16 frame is the
/// standalone app's; why one and not one per mask is not measured. A renderer that fails can leave the mask
/// invisible; `isReadyForDisplay` is how the view finds out that the shield has not drawn, and the view then
/// reports no presentation.
@MainActor enum CaptureShield {
    /// Nil when the frame could not be built; the caller draws the mask without a shield.
    static func make(frame: CGRect) -> AVSampleBufferDisplayLayer? {
        guard let opaqueFrame else { return nil }
        let layer = AVSampleBufferDisplayLayer()
        layer.frame = frame
        layer.videoGravity = .resize
        layer.preventsCapture = true
        layer.sampleBufferRenderer.enqueue(opaqueFrame)
        return layer
    }

    private static let opaqueFrame: CMSampleBuffer? = {
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer, CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess
        else { return nil }
        if let address = CVPixelBufferGetBaseAddress(buffer) {
            memset(address, 255, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer,
                                                            formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary]
        attachments?.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        return sample
    }()
}
