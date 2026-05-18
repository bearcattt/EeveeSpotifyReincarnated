import Foundation
import ObjectiveC
import EeveeSpotifyC

final class SponsorBlockSkipper {
    static let shared = SponsorBlockSkipper()

    private let queue = DispatchQueue(label: "com.eevee.sponsorblock.skipper")
    private var currentEpisodeID: String?
    private var currentSegments: [SponsorBlockSegment] = []
    private var fetchInFlight = false
    private var emptyEpisodeIDs: Set<String> = []
    private var lastSeekMonotonicMs: UInt64 = 0

    private var lastPosition: Double = 0
    private var lastPositionStamp: TimeInterval = 0
    private var lastPlaybackSpeed: Double = 1.0
    private var lastIsPlaying: Bool = false
    private var lastDuration: Double = 0
    private weak var lastPlayer: AnyObject?

    static let segmentsChangedNotification = Notification.Name("EeveeSponsorBlockSegmentsChanged")

    func snapshot() -> (segments: [SponsorBlockSegment], duration: Double, episodeID: String?) {
        queue.sync { (currentSegments, lastDuration, currentEpisodeID) }
    }

    private var pendingSeekTarget: Double?
    private var pendingSeekDeadline: TimeInterval = 0
    private var dismissedUUIDs: Set<String> = []
    private var promptedUUIDs: Set<String> = []

    private var pollTimer: DispatchSourceTimer?
    private var seekSelectorCached: Selector?

    func processStateChange(player: AnyObject, state: AnyObject) {
        let options = UserDefaults.sponsorBlockOptions
        guard options.enabled else { return }

        let trackObj = state.value(forKey: "track") as AnyObject?
        let isPodcast = (trackObj?.value(forKey: "isPodcast") as? Bool) ?? false
        let uriObj = trackObj?.value(forKey: "URI") as AnyObject?
        let uriPreview: String = {
            if let s = uriObj as? String { return s }
            if let u = uriObj as? URL { return u.absoluteString }
            return "nil"
        }()

        guard isPodcast, let uriObj = uriObj else {
            queue.async {
                self.stopPolling()
                let wasActive = (self.currentEpisodeID != nil) || !self.currentSegments.isEmpty
                if wasActive {
                    writeDebugLog("[SB] track changed away (isPodcast=\(isPodcast ? "Y" : "N") uri=\(uriPreview)) — clearing")
                    self.currentEpisodeID = nil
                    self.currentSegments = []
                    self.dismissedUUIDs.removeAll()
                    self.promptedUUIDs.removeAll()
                    self.lastDuration = 0
                    self.lastIsPlaying = false
                    self.pendingSeekTarget = nil
                    self.broadcastSegments()
                }
            }
            return
        }
        let uriString: String = {
            if let s = uriObj as? String { return s }
            if let u = uriObj as? URL { return u.absoluteString }
            return String(describing: uriObj)
        }()
        guard let episodeID = extractEpisodeID(fromURI: uriString) else { return }

        let positionRaw: Double = (state.value(forKey: "position") as? NSNumber)?.doubleValue ?? 0
        let durationRaw: Double = (state.value(forKey: "duration") as? NSNumber)?.doubleValue ?? 0
        let playbackSpeed: Double = (state.value(forKey: "playbackSpeed") as? NSNumber)?.doubleValue ?? 1.0
        let isPlaying: Bool = (state.value(forKey: "isPlaying") as? Bool) ?? false
        let positionSec = normalizeSeconds(positionRaw, durationHint: durationRaw)

        queue.async {
            self.lastPlayer = player
            let now = self.uptimeSec()
            let firstStateForEpisode = (episodeID != self.currentEpisodeID) || (self.lastPositionStamp == 0)
            let expected = self.lastPosition + (now - self.lastPositionStamp) * self.lastPlaybackSpeed
            let delta = positionSec - expected
            let isOwnSeek: Bool = {
                guard let target = self.pendingSeekTarget else { return false }
                if now > self.pendingSeekDeadline { return false }
                return abs(positionSec - target) < 1.5
            }()

            var classification = "tick"
            if firstStateForEpisode { classification = "first" }
            else if isOwnSeek { classification = "ownSeek"; self.pendingSeekTarget = nil }
            else if abs(delta) > 2.0 { classification = "manualSeek" }

            if classification == "manualSeek" || classification == "first" {
                writeDebugLog("[SB] state ep=\(episodeID) pos=\(fmt(positionSec)) playing=\(isPlaying ? "Y" : "N") delta=\(fmtSigned(delta)) -> \(classification)")
            }

            if classification == "manualSeek" && self.lastIsPlaying && options.respectManualSeek {
                for seg in self.currentSegments
                where positionSec >= seg.start && positionSec < seg.end {
                    if self.dismissedUUIDs.insert(seg.uuid).inserted {
                        writeDebugLog("[SB] manual seek into \(seg.category) \(fmt(seg.start))..\(fmt(seg.end)) at \(fmt(positionSec)) — dismissed")
                    }
                }
            }

            self.lastPosition = positionSec
            self.lastPositionStamp = now
            self.lastPlaybackSpeed = playbackSpeed > 0 ? playbackSpeed : 1.0
            self.lastIsPlaying = isPlaying
            let normalizedDuration = self.normalizeSeconds(durationRaw, durationHint: durationRaw)
            if abs(normalizedDuration - self.lastDuration) > 0.5 {
                self.lastDuration = normalizedDuration
                self.broadcastSegments()
            }

            if episodeID != self.currentEpisodeID {
                self.currentEpisodeID = episodeID
                self.currentSegments = []
                self.dismissedUUIDs.removeAll()
                self.promptedUUIDs.removeAll()
                self.pendingSeekTarget = nil
                self.fetchInFlight = false
                self.broadcastSegments()
                writeDebugLog("[SB] new episode \(episodeID)")
                self.fetchSegments(for: episodeID, options: options)
            } else if self.currentSegments.isEmpty
                      && !self.fetchInFlight
                      && !self.emptyEpisodeIDs.contains(episodeID) {
                self.fetchSegments(for: episodeID, options: options)
            }

            if isPlaying && !self.currentSegments.isEmpty {
                self.startPolling()
            } else {
                self.stopPolling()
            }

            if !(classification == "manualSeek" && options.respectManualSeek) {
                self.checkAndSkip(reportedPosition: positionSec, options: options)
            }
        }
    }

    private func startPolling() {
        if pollTimer != nil { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.lastIsPlaying else { return }
            let elapsed = self.uptimeSec() - self.lastPositionStamp
            let est = self.lastPosition + elapsed * self.lastPlaybackSpeed
            self.checkAndSkip(reportedPosition: est, options: UserDefaults.sponsorBlockOptions)
        }
        t.resume()
        pollTimer = t
        writeDebugLog("[SB] polling started")
    }

    private func stopPolling() {
        if let t = pollTimer {
            t.cancel()
            pollTimer = nil
            writeDebugLog("[SB] polling stopped")
        }
    }

    private func checkAndSkip(reportedPosition pos: Double, options: SponsorBlockOptions) {
        guard !currentSegments.isEmpty else { return }
        for seg in currentSegments {
            guard seg.isSkip else { continue }
            guard seg.duration >= options.minSegmentDuration else { continue }
            let action = options.action(for: seg.category)
            guard action == .autoSkip || action == .manualSkip else { continue }
            guard !options.respectManualSeek || !dismissedUUIDs.contains(seg.uuid) else { continue }
            guard pos >= seg.start, pos < (seg.end - 0.25) else { continue }

            if action == .manualSkip {
                promptManualSkip(seg: seg, options: options)
                continue
            }

            // 1.2s cooldown: estimated-position polling can fire twice before
            // the real player tick lands, causing a double-seek.
            let nowMs = monotonicMs()
            if nowMs - lastSeekMonotonicMs < 1200 { return }
            lastSeekMonotonicMs = nowMs

            let targetSec = seg.end + 0.05
            writeDebugLog("[SB] skip cat=\(seg.category) pos=\(fmt(pos)) range=\(fmt(seg.start))..\(fmt(seg.end)) -> \(fmt(targetSec))s")
            if options.logOnly {
                writeDebugLog("[SB] logOnly=true — not seeking")
                return
            }
            guard let player = lastPlayer else {
                writeDebugLog("[SB] no player ref")
                return
            }
            pendingSeekTarget = targetSec
            pendingSeekDeadline = uptimeSec() + 2.5
            seek(player: player, toSeconds: targetSec)
            lastPosition = targetSec
            lastPositionStamp = uptimeSec()
            if options.showToast {
                SponsorBlockToast.shared.show("Skipped \(prettyCategory(seg.category)) (\(Int(seg.duration))s)")
            }
            return
        }
    }

    private func promptManualSkip(seg: SponsorBlockSegment, options: SponsorBlockOptions) {
        guard !promptedUUIDs.contains(seg.uuid) else { return }
        promptedUUIDs.insert(seg.uuid)
        let title = "\(prettyCategory(seg.category)) (\(Int(seg.duration))s)"
        SponsorBlockToast.shared.showAction(message: title, actionTitle: "Skip") { [weak self] in
            self?.queue.async {
                guard let self else { return }
                guard let player = self.lastPlayer else { return }
                let targetSec = seg.end + 0.05
                self.pendingSeekTarget = targetSec
                self.pendingSeekDeadline = self.uptimeSec() + 2.5
                self.seek(player: player, toSeconds: targetSec)
                self.lastPosition = targetSec
                self.lastPositionStamp = self.uptimeSec()
                writeDebugLog("[SB] manual-skip accepted cat=\(seg.category) -> \(fmt(targetSec))s")
            }
        }
    }

    private func fetchSegments(for episodeID: String, options: SponsorBlockOptions) {
        guard !fetchInFlight else { return }
        fetchInFlight = true
        writeDebugLog("[SB] fetching segments for \(episodeID)")
        SponsorBlockAPI.fetchSegments(episodeID: episodeID, options: options) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                self.fetchInFlight = false
                if episodeID != self.currentEpisodeID { return }
                switch result {
                case .success(let segs):
                    self.currentSegments = segs
                    self.broadcastSegments()
                    if segs.isEmpty {
                        self.emptyEpisodeIDs.insert(episodeID)
                        writeDebugLog("[SB] no segments for \(episodeID) (cached empty)")
                    } else {
                        writeDebugLog("[SB] got \(segs.count) segments for \(episodeID)")
                        for s in segs {
                            writeDebugLog("[SB]   - \(s.category) \(fmt(s.start))..\(fmt(s.end)) (\(fmt(s.duration))s)")
                        }
                        if UserDefaults.sponsorBlockOptions.respectManualSeek {
                            let pos = self.lastPosition
                            for seg in segs
                            where pos >= seg.start && pos < seg.end {
                                self.dismissedUUIDs.insert(seg.uuid)
                                writeDebugLog("[SB] already inside \(seg.category) \(fmt(seg.start))..\(fmt(seg.end)) at load — dismissed")
                            }
                        }
                        if self.lastIsPlaying { self.startPolling() }
                    }
                case .failure(let err):
                    writeDebugLog("[SB] fetch failed: \(err)")
                }
            }
        }
    }

    private func seek(player: AnyObject, toSeconds seconds: Double) {
        let sel = resolveSeekSelector(on: player)
        guard let sel else {
            writeDebugLog("[SB] no seek selector on \(String(cString: class_getName(object_getClass(player))))")
            return
        }
        let cls = object_getClass(player)
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        // Spotify variants pass seek as either seconds (Double) or ms (Double).
        // Read the encoded arg type to pick the right unit instead of guessing.
        let argType: String = {
            guard let raw = method_copyArgumentType(method, 2) else { return "?" }
            defer { free(raw) }
            return String(cString: raw)
        }()
        let argDouble = (argType == "d") ? seconds : seconds * 1000.0
        writeDebugLog("[SB] seek -[\(String(cString: class_getName(cls))) \(NSStringFromSelector(sel))] arg=\(fmt(argDouble)) (type=\(argType))")
        EeveeSBInvokeSeekDouble(player, sel, argDouble)
    }

    private func resolveSeekSelector(on player: AnyObject) -> Selector? {
        if let cached = seekSelectorCached, player.responds(to: cached) {
            return cached
        }
        for name in ["seekTo:", "seekToPosition:", "seekToMs:"] {
            let s = NSSelectorFromString(name)
            if player.responds(to: s) {
                seekSelectorCached = s
                return s
            }
        }
        return nil
    }

    private func extractEpisodeID(fromURI uri: String) -> String? {
        if uri.hasPrefix("spotify:episode:") {
            return String(uri.dropFirst("spotify:episode:".count))
        }
        if let r = uri.range(of: "/episode/") {
            return String(uri[r.upperBound...]).split(separator: "?").first.map(String.init)
        }
        return nil
    }

    // Some player observers report seconds, others ms. Use 10_000 as the gate:
    // any audio > 2.7h would exceed this in seconds, but Spotify episodes don't.
    private func normalizeSeconds(_ raw: Double, durationHint: Double) -> Double {
        if raw > 10_000 { return raw / 1000.0 }
        if durationHint > 10_000 { return raw / 1000.0 }
        return raw
    }

    private func monotonicMs() -> UInt64 {
        UInt64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    private func uptimeSec() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }

    private func prettyCategory(_ key: String) -> String {
        switch key {
        case "sponsor":          return "sponsor"
        case "selfpromo":        return "self-promo"
        case "interaction":      return "interaction"
        case "intro":             return "intro"
        case "outro":            return "outro"
        case "preview":          return "preview"
        case "hook":             return "hook"
        case "filler":           return "filler"
        case "exclusive_access": return "exclusive access"
        default:                 return key
        }
    }

    private func broadcastSegments() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SponsorBlockSkipper.segmentsChangedNotification, object: nil)
        }
    }
}

private func fmt(_ d: Double) -> String { String(format: "%.2f", d) }
private func fmtSigned(_ d: Double) -> String { String(format: "%+.2f", d) }
