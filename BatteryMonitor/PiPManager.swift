import Foundation
import AVKit
import UIKit

@MainActor
final class PiPManager: NSObject, ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var pipController: AVPictureInPictureController?
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    override init() {
        super.init()
        configureIfPossible()
    }

    private func configureIfPossible() {
        guard isSupported else { return }

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect

        // IMPORTANT: declare as optional so this compiles whether the initializer returns optional or non-optional.
        let controller: AVPictureInPictureController? = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.delegate = self
        pipController = controller
    }

    func start() {
        guard isSupported else { return }
        if pipController == nil { configureIfPossible() }
        pipController?.startPictureInPicture()
    }

    func stop() {
        pipController?.stopPictureInPicture()
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
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
            self.isActive = false
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            self.isActive = false
        }
    }
}