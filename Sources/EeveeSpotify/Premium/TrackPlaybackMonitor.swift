import Foundation
import Orion

class TrackPlaybackMonitor {
    static let shared = TrackPlaybackMonitor()
    
    private(set) var currentTrackURI: String?
    private var notificationObservers: [NSObjectProtocol] = []
    
    func startMonitoring() {
        let center = NotificationCenter.default
        
        let trackObserver = center.addObserver(
            forName: NSNotification.Name("com.spotify.player.track"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleTrackChange(notification)
        }
        notificationObservers.append(trackObserver)
        
        let stateObserver = center.addObserver(
            forName: NSNotification.Name("com.spotify.player.playbackstate"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handlePlaybackState(notification)
        }
        notificationObservers.append(stateObserver)
        
        let endObserver = center.addObserver(
            forName: NSNotification.Name("com.spotify.playback"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handlePlaybackEvent(notification)
        }
        notificationObservers.append(endObserver)
        
        writeDebugLog("[TPM] Playback monitoring started")
    }
    
    private func handleTrackChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let uri = userInfo["uri"] as? String ?? extractURI(from: userInfo) else {
            return
        }
        
        currentTrackURI = uri
        writeDebugLog("[TPM] Track changed: \(uri)")
        
        let state = OfflineDownloadManager.shared.getState(for: uri)
        if state == .downloading {
            writeDebugLog("[TPM] Download track started playing")
        }
    }
    
    private func handlePlaybackState(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let isPlaying = userInfo["playing"] as? Bool ?? false
        if !isPlaying, let uri = currentTrackURI {
            let state = OfflineDownloadManager.shared.getState(for: uri)
            if state == .downloading {
                writeDebugLog("[TPM] Download track paused/stopped: \(uri)")
            }
        }
    }
    
    private func handlePlaybackEvent(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let uri = userInfo["uri"] as? String,
              let event = userInfo["event"] as? String else {
            return
        }
        
        if event == "end" || event == "stop" {
            let state = OfflineDownloadManager.shared.getState(for: uri)
            if state == .downloading {
                writeDebugLog("[TPM] Download track ended: \(uri)")
                SilentPlaybackController.shared.trackFinished(uri, success: true)
            }
        }
    }
    
    private func extractURI(from userInfo: [AnyHashable: Any]) -> String? {
        if let track = userInfo["track"] as? NSObject {
            if let uri = track.value(forKey: "URI") as? NSURL {
                return uri.absoluteString
            }
        }
        return nil
    }
    
    func stopMonitoring() {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
    }
}
