import Foundation
import AVKit
import CoreMedia
import CoreVideo
import UIKit

final class PiPManager: NSObject, ObservableObject {
    @Published private(set) var isActive: Bool = false
    let isSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()

    private var pipController: AVPictureInPictureController?
    private let displayLayer = AVSampleBufferDisplayLayer()

    private var frameTimer: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var frameIndex: Int64 = 0

    private var videoFormat: CMVideoFormatDescription?
    private var overlayText: String = "Starting…"

    // Render size for PiP video
    private let renderSize = CGSize(width: 720, height: 1280)
    private let fps: Double = 15

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor

        guard isSupported else { return }

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
        guard isSupported, let controller = pipController, !controller.isPictureInPictureActive else { return }

        // Reset
        displayLayer.flushAndRemoveImage()
        frameIndex = 0
        videoFormat = nil

        startTime = CACurrentMediaTime()
        startFramePump()

        controller.startPictureInPicture()
    }

    func stop() {
        guard let controller = pipController, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
        stopFramePump()
    }

    private func startFramePump() {
        stopFramePump()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        // Aim for fps (CADisplayLink is vsync-based; we skip frames)
        link.add(to: .main, forMode: .common)
        frameTimer = link
    }

    private func stopFramePump() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    @objc private func tick() {
        // throttle to fps
        let elapsed = CACurrentMediaTime() - startTime
        let expectedFrames = Int64(elapsed * fps)
        if frameIndex > expectedFrames { return }

        guard let sampleBuffer = makeSampleBuffer(frameIndex: frameIndex) else { return }
        frameIndex += 1

        // Keep queue small
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    private func makeSampleBuffer(frameIndex: Int64) -> CMSampleBuffer? {
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // Background
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Title bar
        ctx.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: 120))

        drawText("Battery Monitor (PiP)", in: ctx, rect: CGRect(x: 24, y: 24, width: width - 48, height: 40),
                 font: UIFont.boldSystemFont(ofSize: 28), color: .white)

        // Body text
        let bodyRect = CGRect(x: 24, y: 140, width: width - 48, height: height - 180)
        drawMultilineText(overlayText, in: ctx, rect: bodyRect, font: UIFont.monospacedSystemFont(ofSize: 22, weight: .regular), color: .white)

        // Create/keep format description
        if videoFormat == nil {
            var fmt: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &fmt)
            videoFormat = fmt
        }
        guard let format = videoFormat else { return nil }

        // Timing (fps)
        let frameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
        let pts = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))

        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr else { return nil }
        return sampleBuffer
    }

    private func drawText(_ text: String, in ctx: CGContext, rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let str = NSAttributedString(string: text, attributes: attrs)
        UIGraphicsPushContext(ctx)
        str.draw(in: rect)
        UIGraphicsPopContext()
    }

    private func drawMultilineText(_ text: String, in ctx: CGContext, rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let str = NSAttributedString(string: text, attributes: attrs)
        UIGraphicsPushContext(ctx)
        str.draw(in: rect)
        UIGraphicsPopContext()
    }
}

// MARK: - AVPictureInPictureControllerDelegate
extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = true }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = false }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        stopFramePump()
        DispatchQueue.main.async { self.isActive = false }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // We continuously generate frames; nothing to toggle for now.
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // "Infinite" live stream
        return CMTimeRange(start: .zero, duration: CMTime.positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // No-op
    }

    // IMPORTANT: correct label is `completion:` (not completionHandler:)
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}