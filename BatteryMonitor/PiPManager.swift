import Foundation
import AVKit
import AVFoundation

@MainActor
final class PiPManager: NSObject, ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastMessage: String?

    private var pipController: AVPictureInPictureController?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    override init() {
        super.init()
        setup()
    }

    private func setup() {
        guard isSupported else {
            lastMessage = "PiP is not supported."
            return
        }

        // If you add a bundled video named "pip.mp4", PiP can actually start.
        if let url = Bundle.main.url(forResource: "pip", withExtension: "mp4") {
            let p = AVPlayer(url: url)
            self.player = p

            let layer = AVPlayerLayer(player: p)
            layer.videoGravity = .resizeAspect
            self.playerLayer = layer

            let controller = AVPictureInPictureController(playerLayer: layer)
            controller.delegate = self
            self.pipController = controller

            lastMessage = "Ready. (Using bundled pip.mp4)"
        } else {
            lastMessage = "Add a bundled video named pip.mp4 to enable real PiP."
        }
    }

    func start() {
        guard isSupported else { return }
        guard let controller = pipController, let player else {
            lastMessage = "PiP not ready. (Missing pip.mp4)"
            return
        }

        player.play()
        controller.startPictureInPicture()
    }

    func stop() {
        pipController?.stopPictureInPicture()
        player?.pause()
    }

    // MARK: - Internal helpers (must run on MainActor)
    private func setActive(_ active: Bool, message: String? = nil) {
        isActive = active
        if let message { lastMessage = message }
    }
}

// Swift 6 isolation fix:
// Make the conformance preconcurrency + make delegate methods nonisolated,
// then hop back to MainActor for state updates.
extension PiPManager: @preconcurrency AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(true, message: "PiP starting…") }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(true, message: "PiP started.") }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(true, message: "PiP stopping…") }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(false, message: "PiP stopped.") }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.setActive(false, message: "PiP failed: \(error.localizedDescription)") }
    }
}