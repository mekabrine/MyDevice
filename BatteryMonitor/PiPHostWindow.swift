import UIKit

/// Minimal placeholder so the file exists and compiles.
/// You can remove this file if you aren’t using a separate window.
final class PiPHostWindow: UIWindow {
    override init(frame: CGRect) {
        super.init(frame: frame)
        windowLevel = .statusBar + 1
        backgroundColor = .clear
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        windowLevel = .statusBar + 1
        backgroundColor = .clear
        isHidden = true
    }