import AVFoundation
import AVKit
import UIKit

@MainActor
final class PiPManager: NSObject, ObservableObject {
    @Published private(set) var isActive: Bool = false

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?

    private var timer: DispatchSourceTimer?
    private var frameIndex: Int64 = 0
    private var videoFormat: CMVideoFormatDescription?

    private var overlayText: String = "Battery Monitor\n(Starting…)"

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    override init() {
        super.init()
        setup()
    }

    private func setup() {
        guard isSupported else { return }

        displayLayer.videoGravity = .resizeAspect

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        pipController = controller
    }

    func setOverlayText(_ text: String) {
        overlayText = text
    }

    func start() {
        guard isSupported else { return }
        guard let pipController else { return }
        if pipController.isPictureInPictureActive { return }

        startFeedingFrames()
        pipController.startPictureInPicture()
    }

    func stop() {
        pipController?.stopPictureInPicture()
        stopFeedingFrames()
    }

    private func startFeedingFrames() {
        stopFeedingFrames()
        frameIndex = 0

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now(), repeating: 1.0) // 1 fps is enough for “status” PiP
        t.setEventHandler { [weak self] in
            self?.enqueueFrame()
        }
        timer = t
        t.resume()
    }

    private func stopFeedingFrames() {
        timer?.cancel()
        timer = nil
    }

    private func enqueueFrame() {
        let size = CGSize(width: 640, height: 360)
        let image = renderOverlayImage(size: size, text: overlayText)

        guard let pixelBuffer = makePixelBuffer(from: image, size: size) else { return }

        if videoFormat == nil {
            var fmt: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &fmt
            )
            videoFormat = fmt
        }

        guard let format = videoFormat else { return }

        let pts = CMTime(value: frameIndex, timescale: 1)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sb = sampleBuffer else { return }

        displayLayer.enqueue(sb)
        frameIndex += 1
    }

    private func renderOverlayImage(size: CGSize, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // subtle border
            UIColor(white: 1.0, alpha: 0.15).setStroke()
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.stroke(CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]

            let smallAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor(white: 1.0, alpha: 0.85),
                .paragraphStyle: paragraph
            ]

            let title = "Battery Monitor (PiP)\n"
            (title as NSString).draw(
                in: CGRect(x: 24, y: 22, width: size.width - 48, height: 60),
                withAttributes: attrs
            )

            (text as NSString).draw(
                in: CGRect(x: 24, y: 86, width: size.width - 48, height: size.height - 120),
                withAttributes: smallAttrs
            )
        }
    }

    private func makePixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )

        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        guard let cg = image.cgImage else { return nil }
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = false
            self.stopFeedingFrames()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            self.isActive = false
            self.stopFeedingFrames()
        }
    }
}

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // We generate frames continuously while active; no-op.
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // “Infinite” time range is fine for a status overlay.
        return CMTimeRange(start: .zero, duration: CMTime.positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // No-op.
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}