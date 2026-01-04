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
        // Without it, the code still compiles and runs, but start() will show a message.
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
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        lastMessage = "PiP starting…"
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        lastMessage = "PiP started."
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        lastMessage = "PiP stopping…"
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        lastMessage = "PiP stopped."
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        lastMessage = "PiP failed: \(error.localizedDescription)"
    }
}