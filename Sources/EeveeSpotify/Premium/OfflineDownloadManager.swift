import Foundation
import CommonCrypto

class OfflineDownloadManager {
    static let shared = OfflineDownloadManager()
    
    private var downloadedTracks: Set<String> = []
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
    
    /// Track a URI as intentionally downloaded
    func markForDownload(_ uri: String) {
        stateLock.lock()
        downloadedTracks.insert(uri)
        stateLock.unlock()
        saveState()
        writeDebugLog("[ODM] Marked for download: \(uri)")
    }
    
    /// Remove download tracking
    func removeDownload(_ uri: String) {
        stateLock.lock()
        downloadedTracks.remove(uri)
        if let urls = uriToCachedURLs.removeValue(forKey: uri) {
            for urlHash in urls {
                try? FileManager.default.removeItem(at: cacheFileURL(for: urlHash))
                try? FileManager.default.removeItem(at: cacheFileURL(for: urlHash + "_meta"))
            }
        }
        stateLock.unlock()
        saveState()
    }
    
    /// Check if a URI is downloaded
    func isDownloaded(_ uri: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return downloadedTracks.contains(uri)
    }
    
    /// URL hash → cache file path
    func cacheFileURL(for hash: String) -> URL {
        audioCacheDir.appendingPathComponent("\(hash).bin")
    }
    
    /// Check if a CDN URL body is cached
    func hasCachedAudio(for urlHash: String) -> Bool {
        FileManager.default.fileExists(atPath: cacheFileURL(for: urlHash).path)
    }
    
    /// Store audio CDN response body
    func cacheAudioResponse(urlHash: String, data: Data, contentType: String?) {
        let fileURL = cacheFileURL(for: urlHash)
        try? data.write(to: fileURL, options: .atomic)
        if let ct = contentType {
            let meta = ["contentType": ct].data(using: .utf8)
            try? meta?.write(to: cacheFileURL(for: urlHash + "_meta"), options: .atomic)
        }
        writeDebugLog("[ODM] Cached audio: \(urlHash) (\(data.count) bytes)")
    }
    
    /// Retrieve cached audio response body
    func getCachedAudio(urlHash: String) -> Data? {
        let url = cacheFileURL(for: urlHash)
        return try? Data(contentsOf: url)
    }
    
    /// Get cached content type
    func getCachedContentType(urlHash: String) -> String? {
        let metaURL = cacheFileURL(for: urlHash + "_meta")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return meta["contentType"] ?? "audio/ogg"
    }
    
    /// Associate a playing track URI with audio CDN URLs
    func associateURIToURL(_ uri: String, urlHash: String) {
        stateLock.lock()
        if uriToCachedURLs[uri] == nil {
            uriToCachedURLs[uri] = []
        }
        uriToCachedURLs[uri]?.insert(urlHash)
        stateLock.unlock()
    }
    
    /// Get all cached URL hashes for a URI
    func getCachedURLs(for uri: String) -> Set<String> {
        stateLock.lock(); defer { stateLock.unlock() }
        return uriToCachedURLs[uri] ?? []
    }
    
    /// Get total cache size
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
    
    /// Number of downloaded tracks
    var downloadedCount: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return downloadedTracks.count
    }
    
    /// All downloaded URIs
    var allDownloads: [String] {
        stateLock.lock(); defer { stateLock.unlock() }
        return Array(downloadedTracks)
    }
    
    /// Clear everything
    func clearAll() {
        stateLock.lock()
        downloadedTracks.removeAll()
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
        if let index = dict["index"] as? [String: [String]] {
            uriToCachedURLs = index.mapValues { Set($0) }
        }
    }
}

/// Helper to hash a URL string for use as cache key
func audioURLHash(_ url: URL) -> String {
    let s = url.absoluteString
    let data = Data(s.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buf in
        _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
    }
    return String(hash.prefix(16).map { String(format: "%02x", $0) }.joined())
}
