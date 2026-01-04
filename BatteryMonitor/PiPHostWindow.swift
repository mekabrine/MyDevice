import UIKit

final class PiPHostWindow: UIWindow {
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        windowLevel = .normal
        backgroundColor = .clear
        isHidden = false
    }
}