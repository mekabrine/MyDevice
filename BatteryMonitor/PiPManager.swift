import Foundation
import AVFoundation
import AVKit
import UIKit

@MainActor
final class PiPManager: NSObject, ObservableObject {
    static let shared = PiPManager()

    @Published private(set) var isActive: Bool = false

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var controller: AVPictureInPictureController?

    // Backing video URL (wide, black) written to temp once.
    private var videoURL: URL?

    // MARK: - Public API

    func startPiP() {
        // Already active / already have a controller
        if controller?.isPictureInPictureActive == true { return }

        do {
            let url = try prepareBlankVideoIfNeeded()
            videoURL = url

            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .none

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect

            self.player = player
            self.playerLayer = layer

            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                return
            }

            let pip = AVPictureInPictureController(playerLayer: layer)
            pip.delegate = self
            self.controller = pip

            // Loop the blank video
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(loopVideo),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item
            )

            player.play()
            pip.startPictureInPicture()
        } catch {
            // If something fails, ensure we clean up.
            stopPiP()
        }
    }

    func stopPiP() {
        controller?.stopPictureInPicture()
        cleanup()
    }

    // MARK: - Internals

    @objc private func loopVideo() {
        player?.seek(to: .zero)
        player?.play()
    }

    private func cleanup() {
        NotificationCenter.default.removeObserver(self)

        controller = nil
        playerLayer = nil
        player?.pause()
        player = nil

        isActive = false
    }

    /// Creates a wide, black mp4 in the temp directory if not already present.
    private func prepareBlankVideoIfNeeded() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("pip_blank_2400x1000.mp4")

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        try renderBlankVideo(
            outputURL: url,
            width: 2400,
            height: 1000,
            seconds: 10
        )

        return url
    }

    /// Renders a solid-black H.264 mp4 with the given dimensions and duration.
    private func renderBlankVideo(outputURL: URL, width: Int, height: Int, seconds: Int) throws {
        // Remove old file if it exists
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "PiPManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
        }
        writer.add(input)

        if !writer.startWriting() {
            throw writer.error ?? NSError(domain: "PiPManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "startWriting failed"])
        }

        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let totalFrames = seconds * Int(fps)

        // Make a single black pixel buffer to reuse.
        func makeBlackBuffer() -> CVPixelBuffer? {
            var pb: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                sourceAttributes as CFDictionary,
                &pb
            )
            guard status == kCVReturnSuccess, let buffer = pb else { return nil }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return buffer
        }

        guard let blackBuffer = makeBlackBuffer() else {
            throw NSError(domain: "PiPManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }

        let queue = DispatchQueue(label: "pip.blank.render")

        input.requestMediaDataWhenReady(on: queue) {
            var frame = 0
            while input.isReadyForMoreMediaData && frame < totalFrames {
                let time = CMTime(value: CMTimeValue(frame), timescale: fps)
                adaptor.append(blackBuffer, withPresentationTime: time)
                frame += 1
            }

            if frame >= totalFrames {
                input.markAsFinished()
                writer.finishWriting {
                    // nothing else needed
                }
            }
        }

        // Wait until done (simple blocking wait for file to exist and be finalized).
        // NOTE: This runs only when user turns on PiP, so it’s acceptable here.
        while writer.status == .writing {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "PiPManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Video render failed"])
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: @preconcurrency AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = false
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.cleanup()
        }
    }
}