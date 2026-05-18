import UIKit

private let overlayTag = "EeveeSBOverlay"

final class SponsorBlockOverlay {
    static let shared = SponsorBlockOverlay()

    private var trackedSliders: NSHashTable<UIView> = NSHashTable.weakObjects()

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshAll),
            name: SponsorBlockSkipper.segmentsChangedNotification,
            object: nil
        )
    }

    func attach(to slider: UIView) {
        let before = trackedSliders.allObjects.count
        trackedSliders.add(slider)
        if trackedSliders.allObjects.count != before {
            writeDebugLog("[SB] tracked slider count=\(trackedSliders.allObjects.count) bounds=\(NSCoder.string(for: slider.bounds))")
            for (i, sv) in slider.subviews.enumerated() {
                writeDebugLog("[SB]   sv[\(i)] \(NSStringFromClass(type(of: sv))) frame=\(NSCoder.string(for: sv.frame))")
            }
        }

        let snap = SponsorBlockSkipper.shared.snapshot()
        let opts = UserDefaults.sponsorBlockOptions
        let wantDraw = opts.enabled && opts.showOverlay && snap.duration > 0 && !snap.segments.isEmpty
        let hasStale = slider.subviews.contains { $0.accessibilityIdentifier == overlayTag }
        if !wantDraw && !hasStale { return }

        update(slider: slider)
    }

    @objc private func refreshAll() {
        if Thread.isMainThread {
            doRefresh()
        } else {
            DispatchQueue.main.async { [weak self] in self?.doRefresh() }
        }
    }

    private func doRefresh() {
        for s in trackedSliders.allObjects { update(slider: s) }
    }

    func update(slider: UIView) {
        let opts = UserDefaults.sponsorBlockOptions
        slider.subviews
            .filter { $0.accessibilityIdentifier == overlayTag }
            .forEach { $0.removeFromSuperview() }

        guard opts.enabled, opts.showOverlay else { return }

        let snap = SponsorBlockSkipper.shared.snapshot()
        guard snap.duration > 0, !snap.segments.isEmpty else { return }

        let trackFrame = innerTrackFrame(in: slider)
        let container = UIView(frame: trackFrame)
        container.accessibilityIdentifier = overlayTag
        container.isUserInteractionEnabled = false
        container.backgroundColor = .clear
        container.layer.zPosition = 1

        let w = trackFrame.width
        let h = trackFrame.height
        for seg in snap.segments {
            guard seg.isSkip, opts.action(for: seg.category) != .disabled else { continue }
            let x = CGFloat(seg.start / snap.duration) * w
            let segW = max(2, CGFloat((seg.end - seg.start) / snap.duration) * w)
            let bar = UIView(frame: CGRect(x: x, y: 0, width: segW, height: h))
            bar.backgroundColor = UIColor.fromHex(opts.color(for: seg.category)).withAlphaComponent(0.65)
            bar.layer.cornerRadius = min(1, h / 2)
            bar.isUserInteractionEnabled = false
            container.addSubview(bar)
        }

        slider.addSubview(container)
        slider.bringSubviewToFront(container)
    }

    private func innerTrackFrame(in slider: UIView) -> CGRect {
        for sv in slider.subviews {
            let name = NSStringFromClass(type(of: sv))
            if name.contains("AudioView") || name.contains("ProgressTrack") {
                return sv.frame
            }
        }
        let h: CGFloat = max(2, min(4, slider.bounds.height))
        return CGRect(x: 0, y: (slider.bounds.height - h) / 2,
                      width: slider.bounds.width, height: h)
    }
}

extension UIColor {
    static func fromHex(_ hex: String) -> UIColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .gray }
        let r = CGFloat((v & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((v & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(v & 0x0000FF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}
