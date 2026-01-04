import UIKit

final class PiPOverlayViewController: UIViewController {
    private let rateLabel = UILabel()
    private let etaLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        rateLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        rateLabel.textColor = .white
        rateLabel.numberOfLines = 1

        etaLabel.font = .systemFont(ofSize: 15, weight: .regular)
        etaLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        etaLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [rateLabel, etaLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func update(rateLine: String, etaLine: String) {
        if isViewLoaded {
            rateLabel.text = rateLine
            etaLabel.text = etaLine
        } else {
            _ = view
            rateLabel.text = rateLine
            etaLabel.text = etaLine
        }
    }
}
