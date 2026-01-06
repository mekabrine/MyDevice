import Foundation
import AVFoundation
import AVKit

/// Starts a looping video and (optionally) enters Picture-in-Picture.
/// Note: PiP is for video playback. It does not guarantee unlimited background execution.
final class PiPKeepAlive: NSObject {
    static let shared = PiPKeepAlive()

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var pip: AVPictureInPictureController?

    func startPiP() {
        // Audio session is commonly required for background playback.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)

        // Add BatteryMonitor/silent.mp4 to your app target (Resources).
        guard let url = Bundle.main.url(forResource: "silent", withExtension: "mp4") else {
            assertionFailure("Missing silent.mp4. Add BatteryMonitor/silent.mp4 and include it in the target.")
            return
        }

        let item = AVPlayerItem(url: url)
        let qp = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: qp, templateItem: item)

        let layer = AVPlayerLayer(player: qp)
        layer.videoGravity = .resizeAspect

        // PiP supported?
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            qp.play()
            self.queuePlayer = qp
            self.looper = looper
            self.playerLayer = layer
            return
        }

        let pip = AVPictureInPictureController(playerLayer: layer)

        self.queuePlayer = qp
        self.looper = looper
        self.playerLayer = layer
        self.pip = pip

        qp.play()
        pip.startPictureInPicture()
    }

    func stopPiP() {
        pip?.stopPictureInPicture()
        queuePlayer?.pause()

        queuePlayer = nil
        looper = nil
        playerLayer = nil
        pip = nil

        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
