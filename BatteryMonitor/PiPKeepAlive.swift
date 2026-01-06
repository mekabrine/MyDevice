import AVFoundation
import AVKit
import UIKit

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

    @MainActor
    func start() {
        lastError = nil

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            lastError = "PiP not supported on this device."
            return
        }

        guard let url = Bundle.main.url(forResource: "silent", withExtension: "mp4") else {
            lastError = "silent.mp4 not found in app bundle (ensure it’s in Copy Bundle Resources)."
            return
        }

        // IMPORTANT: Do not try to construct a UIWindowScene manually (UIKit marks those inits unavailable).
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            lastError = "No active UIWindowScene available."
            return
        }

        // Create a tiny off-screen window to host the player layer.
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        window.windowLevel = .alert + 1
        window.isHidden = false

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
            cleanupOnMain()
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
        pip.startPictureInPicture()
    }

    @MainActor
    func stop() {
        pipController?.stopPictureInPicture()
        cleanupOnMain()
    }

    @objc private func loopItem() {
        // Called by NotificationCenter; ensure main for UI/player ops.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.player?.seek(to: .zero)
            self.player?.play()
        }
    }

    @MainActor
    private func cleanupOnMain() {
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

// Mark conformance as preconcurrency to avoid Swift 6 actor-isolation checking warnings,
// and manually hop to main for state/UI updates.
extension PiPKeepAlive: @preconcurrency AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in
            self?.isPictureInPictureActive = true
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = "PiP failed to start: \(error.localizedDescription)"
            self?.isPictureInPictureActive = false
            Task { @MainActor in
                self?.cleanupOnMain()
            }
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in
            self?.isPictureInPictureActive = false
            Task { @MainActor in
                self?.cleanupOnMain()
            }
        }
    }
}
