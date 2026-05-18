import UIKit

final class SponsorBlockToast {
    static let shared = SponsorBlockToast()
    private weak var current: UIView?
    private var dismissWork: DispatchWorkItem?
    private var actionHandler: (() -> Void)?

    func show(_ message: String) {
        DispatchQueue.main.async { self.presentOnMain(message: message, actionTitle: nil, action: nil) }
    }

    func showAction(message: String, actionTitle: String, action: @escaping () -> Void) {
        DispatchQueue.main.async { self.presentOnMain(message: message, actionTitle: actionTitle, action: action) }
    }

    private func presentOnMain(message: String, actionTitle: String?, action: (() -> Void)?) {
        guard let window = activeKeyWindow() else { return }

        current?.removeFromSuperview()
        dismissWork?.cancel()
        actionHandler = action

        let toast = UIView()
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        toast.layer.cornerRadius = 14
        toast.layer.masksToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0
        toast.isUserInteractionEnabled = true
        toast.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.numberOfLines = 2
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false

        toast.addSubview(label)
        window.addSubview(toast)

        var constraints: [NSLayoutConstraint] = [
            toast.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toast.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 12),
            toast.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, multiplier: 0.9),
            label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -10),
        ]

        if let actionTitle, action != nil {
            let btn = UIButton(type: .system)
            btn.setTitle(actionTitle, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.setTitleColor(UIColor(red: 0.18, green: 0.84, blue: 0.45, alpha: 1), for: .normal)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
            toast.addSubview(btn)
            constraints += [
                btn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 14),
                btn.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -16),
                btn.centerYAnchor.constraint(equalTo: toast.centerYAnchor),
            ]
        } else {
            constraints += [label.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -16)]
        }

        NSLayoutConstraint.activate(constraints)
        current = toast

        UIView.animate(withDuration: 0.2) { toast.alpha = 1 }

        let lifetime: TimeInterval = (actionTitle == nil) ? 2.2 : 6.0
        let work = DispatchWorkItem { [weak toast] in
            guard let toast else { return }
            UIView.animate(withDuration: 0.25, animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
    }

    @objc private func handleTap() {
        dismiss()
    }

    @objc private func handleAction() {
        actionHandler?()
        actionHandler = nil
        dismiss()
    }

    private func dismiss() {
        dismissWork?.cancel()
        guard let toast = current else { return }
        UIView.animate(withDuration: 0.15, animations: { toast.alpha = 0 }) { _ in
            toast.removeFromSuperview()
        }
    }

    private func activeKeyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene,
                  ws.activationState == .foregroundActive else { continue }
            if let key = ws.windows.first(where: { $0.isKeyWindow }) { return key }
            if let any = ws.windows.first { return any }
        }
        return nil
    }
}
