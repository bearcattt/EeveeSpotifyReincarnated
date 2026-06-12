import Foundation
import CommonCrypto
import UIKit
import AVFoundation

enum DownloadState: String {
    case none
    case downloading
    case completed
    case failed
}

class OfflineDownloadManager {
    static let shared = OfflineDownloadManager()

    private var downloadedTracks: Set<String> = []
    private var downloadingTracks: Set<String> = []
    private var uriToCachedURLs: [String: Set<String>] = [:]
    private let stateLock = NSLock()

    let offlineDir: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("EeveeOffline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    let audioCacheDir: URL
    private let metadataURL: URL
    private let indexURL: URL

    private init() {
        audioCacheDir = offlineDir.appendingPathComponent("AudioCache", isDirectory: true)
        metadataURL = offlineDir.appendingPathComponent("downloads.json")
        indexURL = offlineDir.appendingPathComponent("uri_index.json")
        try? FileManager.default.createDirectory(at: audioCacheDir, withIntermediateDirectories: true)
        loadState()
        writeDebugLog("[ODM] Network cache mode at \(audioCacheDir.path)")
    }

    func getState(for uri: String) -> DownloadState {
        stateLock.lock(); defer { stateLock.unlock() }
        if downloadedTracks.contains(uri) { return .completed }
        if downloadingTracks.contains(uri) { return .downloading }
        return .none
    }

    func handleDownloadToggle(uri: URL) {
        let uriString = uri.absoluteString
        stateLock.lock()
        if downloadedTracks.contains(uriString) {
            stateLock.unlock()
            removeDownload(uriString)
            writeDebugLog("[ODM] Removed download: \(uriString)")
            return
        }
        downloadingTracks.insert(uriString)
        stateLock.unlock()
        saveState()
        writeDebugLog("[ODM] Download toggled: \(uriString)")
        SilentPlaybackController.shared.startDownload(for: uriString)
        DownloadProgressToast.show(message: "⏳ Downloading: \(uriString)")
    }

    func markDownloadComplete(_ uri: String, filePath: String) {
        stateLock.lock()
        downloadingTracks.remove(uri)
        downloadedTracks.insert(uri)
        stateLock.unlock()
        saveState()
        writeDebugLog("[ODM] Download complete: \(uri)")
    }

    func markForDownload(_ uri: String) {
        stateLock.lock()
        downloadingTracks.insert(uri)
        stateLock.unlock()
        saveState()
        writeDebugLog("[ODM] Marked for download: \(uri)")
    }

    func removeDownload(_ uri: String) {
        stateLock.lock()
        downloadedTracks.remove(uri)
        downloadingTracks.remove(uri)
        if let urls = uriToCachedURLs.removeValue(forKey: uri) {
            for urlHash in urls {
                try? FileManager.default.removeItem(at: cacheFileURL(for: urlHash))
                try? FileManager.default.removeItem(at: cacheFileURL(for: urlHash + "_meta"))
            }
        }
        stateLock.unlock()
        saveState()
    }

    func isDownloaded(_ uri: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return downloadedTracks.contains(uri)
    }

    func cacheFileURL(for hash: String) -> URL {
        audioCacheDir.appendingPathComponent("\(hash).bin")
    }

    func hasCachedAudio(for urlHash: String) -> Bool {
        FileManager.default.fileExists(atPath: cacheFileURL(for: urlHash).path)
    }

    func cacheAudioResponse(urlHash: String, data: Data, contentType: String?) {
        let fileURL = cacheFileURL(for: urlHash)
        try? data.write(to: fileURL, options: .atomic)
        if let ct = contentType {
            let meta: [String: String] = ["contentType": ct]
            if let metaData = try? JSONEncoder().encode(meta) {
                try? metaData.write(to: cacheFileURL(for: urlHash + "_meta"), options: .atomic)
            }
        }
        writeDebugLog("[ODM] Cached audio: \(urlHash) (\(data.count) bytes)")
    }

    func getCachedAudio(urlHash: String) -> Data? {
        let url = cacheFileURL(for: urlHash)
        return try? Data(contentsOf: url)
    }

    func getCachedContentType(urlHash: String) -> String? {
        let metaURL = cacheFileURL(for: urlHash + "_meta")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return meta["contentType"] ?? "audio/ogg"
    }

    func associateURIToURL(_ uri: String, urlHash: String) {
        stateLock.lock()
        if uriToCachedURLs[uri] == nil {
            uriToCachedURLs[uri] = []
        }
        uriToCachedURLs[uri]?.insert(urlHash)
        stateLock.unlock()
    }

    func getCachedURLs(for uri: String) -> Set<String> {
        stateLock.lock(); defer { stateLock.unlock() }
        return uriToCachedURLs[uri] ?? []
    }

    func cacheSize() -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: audioCacheDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    var downloadedCount: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return downloadedTracks.count
    }

    var allDownloads: [String] {
        stateLock.lock(); defer { stateLock.unlock() }
        return Array(downloadedTracks)
    }

    func clearAll() {
        stateLock.lock()
        downloadedTracks.removeAll()
        downloadingTracks.removeAll()
        uriToCachedURLs.removeAll()
        stateLock.unlock()
        try? FileManager.default.removeItem(at: audioCacheDir)
        try? FileManager.default.createDirectory(at: audioCacheDir, withIntermediateDirectories: true)
        saveState()
        writeDebugLog("[ODM] All downloads cleared")
    }

    private func saveState() {
        stateLock.lock()
        let dict: [String: Any] = [
            "downloaded": Array(downloadedTracks),
            "downloading": Array(downloadingTracks),
            "index": uriToCachedURLs.mapValues { Array($0) }
        ]
        stateLock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: metadataURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let downloaded = dict["downloaded"] as? [String] {
            downloadedTracks = Set(downloaded)
        }
        if let downloading = dict["downloading"] as? [String] {
            downloadingTracks = Set(downloading)
        }
        if let index = dict["index"] as? [String: [String]] {
            uriToCachedURLs = index.mapValues { Set($0) }
        }
    }
}

class SilentPlaybackController {
    static let shared = SilentPlaybackController()

    private let player = AVPlayer()
    private var downloadQueue: [String] = []
    private var isPlaying = false

    func startDownload(for uri: String) {
        guard let url = URL(string: "spotify://\(uri)") else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                writeDebugLog("[SPC] Opened URI: \(uri) success=\(success)")
            }
        }
    }

    func trackFinished(_ uri: String, success: Bool) {
        if success {
            OfflineDownloadManager.shared.markDownloadComplete(uri, filePath: "")
            DownloadProgressToast.show(message: "✅ Downloaded: \(uri) (\(OfflineDownloadManager.shared.downloadedCount) total)")
        }
    }

    func queueNext(_ uri: String) {
        downloadQueue.append(uri)
        if !isPlaying { playNext() }
    }

    private func playNext() {
        guard !downloadQueue.isEmpty else { isPlaying = false; return }
        isPlaying = true
        let uri = downloadQueue.removeFirst()
        startDownload(for: uri)
    }
}

class DownloadProgressToast {
    static func show(message: String) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.backgroundColor = UIColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 0.9)
            label.textAlignment = .center
            label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            label.numberOfLines = 0
            label.frame = CGRect(x: 20, y: 60, width: window.frame.width - 40, height: 50)
            label.layer.cornerRadius = 10
            label.layer.masksToBounds = true
            window.addSubview(label)
            UIView.animate(withDuration: 0.3, delay: 2.5, options: .curveEaseIn) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
}

func audioURLHash(_ url: URL) -> String {
    let s = url.absoluteString
    let data = Data(s.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buf in
        _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
    }
    return String(hash.prefix(16).map { String(format: "%02x", $0) }.joined())
}
