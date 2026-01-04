import UIKit
import AVFoundation

/// A tiny offscreen window to host the AVPlayerLayer required for PiP.
/// This keeps the implementation self-contained and avoids wiring into the main UI.
final class PiPHostWindow: UIWindow {
    static let shared = PiPHostWindow()

    private let hostVC = UIViewController()
    private var attached = false

    private override init(frame: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10)) {
        super.init(frame: frame)
        windowLevel = .normal
        rootViewController = hostVC
        isHidden = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(playerLayer: AVPlayerLayer, overlayView: UIView) {
        if !attached {
            isHidden = false
            attached = true
        }
        hostVC.view.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        hostVC.view.subviews.forEach { $0.removeFromSuperview() }

        playerLayer.frame = hostVC.view.bounds
        playerLayer.backgroundColor = UIColor.black.cgColor
        hostVC.view.layer.addSublayer(playerLayer)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        hostVC.view.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: hostVC.view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: hostVC.view.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: hostVC.view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: hostVC.view.bottomAnchor)
        ])
    }

    func detach() {
        hostVC.view.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        hostVC.view.subviews.forEach { $0.removeFromSuperview() }
        isHidden = true
        attached = false
    }
}
