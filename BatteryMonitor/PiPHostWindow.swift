import UIKit

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
}