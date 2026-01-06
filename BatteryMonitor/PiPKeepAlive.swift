import AVFoundation
import AVKit
import UIKit

@MainActor
final class PiPKeepAlive: NSObject, ObservableObject {
    static let shared = PiPKeepAlive()

    @Published private(set) var isPictureInPictureActive: Bool = false
    @Published private(set) var lastError: String?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?

    private var hostWindow: UIWindow?
    private var hostViewController: UIViewController?

    private override init() {
        super.init()
    }

    func start() {
        lastError = nil

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            lastError = "PiP not supported on this device."
            return
        }

        guard let url = Bundle.main.url(forResource: "silent", withExtension: "mp4") else {
            lastError = "silent.mp4 not found in app bundle (make sure it’s in Copy Bundle Resources)."
            return
        }

        // Create an off-screen window to host the player layer.
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        let window = UIWindow(windowScene: windowScene ?? UIWindowScene(session: .init(), connectionOptions: .init()))
        window.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        window.isHidden = false
        window.windowLevel = .alert + 1

        let vc = UIViewController()
        vc.view.backgroundColor = .black
        window.rootViewController = vc

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopItem),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        let layer = AVPlayerLayer(player: player)
        layer.frame = vc.view.bounds
        layer.videoGravity = .resizeAspectFill
        vc.view.layer.addSublayer(layer)

        guard let pip = AVPictureInPictureController(playerLayer: layer) else {
            lastError = "Failed to create AVPictureInPictureController."
            cleanup()
            return
        }

        pip.delegate = self

        // Keep references
        self.hostWindow = window
        self.hostViewController = vc
        self.player = player
        self.playerLayer = layer
        self.pipController = pip

        player.play()

        // Attempt to start PiP. (User may still need to trigger PiP depending on OS state.)
        pip.startPictureInPicture()
    }

    func stop() {
        pipController?.stopPictureInPicture()
        cleanup()
    }

    @objc private func loopItem() {
        player?.seek(to: .zero)
        player?.play()
    }

    private func cleanup() {
        NotificationCenter.default.removeObserver(self)

        player?.pause()
        player = nil

        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        pipController?.delegate = nil
        pipController = nil

        hostWindow?.isHidden = true
        hostWindow = nil
        hostViewController = nil

        isPictureInPictureActive = false
    }
}

extension PiPKeepAlive: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPictureInPictureActive = true
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        lastError = "PiP failed to start: \(error.localizedDescription)"
        isPictureInPictureActive = false
        cleanup()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPictureInPictureActive = false
        cleanup()
    }
}
