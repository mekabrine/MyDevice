import Foundation
import UIKit
import AVFoundation
import AVKit

/// PiP helper that plays a generated black video at a wide aspect ratio and draws text overlays.
/// Notes:
/// - PiP requires enabling "Audio, AirPlay, and Picture in Picture" under Background Modes.
/// - PiP behavior varies by iOS version/device; the system may stop PiP at any time.
@MainActor
final class PiPManager: NSObject, ObservableObject {
    @Published private(set) var isPiPActive: Bool = false

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?

    private let overlayVC = PiPOverlayViewController()

    func startPiP(rateLine: String, etaLine: String) {
        // If already active, just update text
        updateOverlay(rateLine: rateLine, etaLine: etaLine)
        if isPiPActive { return }

        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        // Create a temporary black video file (wide aspect) if needed
        let url = Self.ensureBlackVideo()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none

        // Loop
        NotificationCenter.default.addObserver(self, selector: #selector(loopVideo(_:)), name: .AVPlayerItemDidPlayToEndTime, object: item)

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect

        // Use a tiny hidden hosting window to own the layer + overlay.
        // PiP needs a player layer; overlay is drawn above it in a separate view.
        let host = PiPHostWindow.shared
        host.attach(playerLayer: layer, overlayView: overlayVC.view)

        self.player = player
        self.playerLayer = layer

        let controller = AVPictureInPictureController(playerLayer: layer)
        controller.delegate = self
        self.pipController = controller

        overlayVC.update(rateLine: rateLine, etaLine: etaLine)

        player.play()
        controller.startPictureInPicture()
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
        player?.pause()
        cleanup()
    }

    func updateOverlay(rateLine: String, etaLine: String) {
        overlayVC.update(rateLine: rateLine, etaLine: etaLine)
    }

    @objc private func loopVideo(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem else { return }
        item.seek(to: .zero, completionHandler: nil)
        player?.play()
    }

    private func cleanup() {
        isPiPActive = false
        pipController = nil
        playerLayer = nil
        player = nil
        PiPHostWindow.shared.detach()
    }

    // MARK: - Black video generation

    /// Generates/returns a black mp4 in tmp with a wide aspect ratio (2.0:1).
    private static func ensureBlackVideo() -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("pip_black_2000x1000.mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        // Create a 1-second black video using AVAssetWriter.
        let size = CGSize(width: 2000, height: 1000) // wide, not tall
        let durationSeconds: Double = 1.0
        let fps: Int32 = 30

        do {
            try generateBlackVideo(url: url, size: size, durationSeconds: durationSeconds, fps: fps)
        } catch {
            // If generation fails, fall back to an empty file (PiP may fail).
            _ = try? Data().write(to: url)
        }
        return url
    }

    private static func generateBlackVideo(url: URL, size: CGSize, durationSeconds: Double, fps: Int32) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        guard writer.canAdd(input) else { throw NSError(domain: "PiP", code: 1) }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(durationSeconds * Double(fps))
        let frameDuration = CMTime(value: 1, timescale: fps)

        func makeBlackBuffer() -> CVPixelBuffer? {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
            guard let pixelBuffer = pb else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, 0, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return pixelBuffer
        }

        let queue = DispatchQueue(label: "pip.video.write")
        let group = DispatchGroup()
        group.enter()

        input.requestMediaDataWhenReady(on: queue) {
            var frame = 0
            while input.isReadyForMoreMediaData && frame < frameCount {
                let time = CMTimeMultiply(frameDuration, multiplier: Int32(frame))
                if let buffer = makeBlackBuffer() {
                    adaptor.append(buffer, withPresentationTime: time)
                }
                frame += 1
            }
            if frame >= frameCount {
                input.markAsFinished()
                writer.finishWriting {
                    group.leave()
                }
            }
        }

        group.wait()
        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "PiP", code: 2)
        }
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
        cleanup()
    }
}
