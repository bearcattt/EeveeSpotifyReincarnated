import Foundation
import AVFoundation
import Orion

private var trackedEngines = NSHashTable<AVAudioEngine>(options: .weakMemory)

class AudioCaptureManager {
    static let shared = AudioCaptureManager()
    
    private var installedTaps = NSMapTable<AVAudioEngine, NSString>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private let fileQueue = DispatchQueue(label: "com.eeveespotify.audiofile")
    private var currentFile: AVAudioFile?
    private var currentCaptureURI: String?
    private let tapLock = NSLock()
    
    func installTapIfNeeded(on engine: AVAudioEngine) {
        tapLock.lock()
        let trackURI = TrackPlaybackMonitor.shared.currentTrackURI
        guard let uri = trackURI else { tapLock.unlock(); return }
        
        let state = OfflineDownloadManager.shared.getState(for: uri)
        guard state == .downloading else { tapLock.unlock(); return }
        
        if installedTaps.object(forKey: engine) != nil { tapLock.unlock(); return }
        tapLock.unlock()
        
        let outputNode = engine.outputNode
        let hardwareFormat = outputNode.outputFormat(forBus: 0)
        let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: hardwareFormat.channelCount,
            interleaved: false
        ) ?? hardwareFormat
        
        let fileName = "\(uri.md5).caf"
        let fileURL = OfflineDownloadManager.shared.audioCacheDir.appendingPathComponent(fileName)
        
        var file: AVAudioFile?
        do {
            try? FileManager.default.removeItem(at: fileURL)
            file = try AVAudioFile(forWriting: fileURL, settings: captureFormat.settings)
        } catch {
            writeDebugLog("[ACM] File create error: \(error)")
            return
        }
        
        tapLock.lock()
        currentCaptureURI = uri
        currentFile = file
        installedTaps.setObject(uri as NSString, forKey: engine)
        tapLock.unlock()
        
        outputNode.installTap(onBus: 0, bufferSize: 4096, format: captureFormat) { [weak self] buffer, _ in
            guard let self = self, let f = self.currentFile else { return }
            self.fileQueue.async {
                do { try f.write(from: buffer) }
                catch { writeDebugLog("[ACM] Write error: \(error)") }
            }
        }
        
        writeDebugLog("[ACM] Audio tap installed for download: \(uri)")
    }
    
    func removeTap(from engine: AVAudioEngine) {
        tapLock.lock()
        let captureURI = currentCaptureURI
        currentFile = nil
        currentCaptureURI = nil
        if installedTaps.object(forKey: engine) != nil {
            installedTaps.removeObject(forKey: engine)
        }
        tapLock.unlock()
        
        engine.outputNode.removeTap(onBus: 0)
        
        if let trackURI = captureURI {
            let fileURL = OfflineDownloadManager.shared.audioCacheDir.appendingPathComponent("\(trackURI.md5).caf")
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int64 ?? 0
            if fileExists && fileSize > 4096 {
                OfflineDownloadManager.shared.markDownloadComplete(trackURI, filePath: fileURL.path)
                SilentPlaybackController.shared.trackFinished(trackURI, success: true)
                writeDebugLog("[ACM] Download complete: \(trackURI) (\(fileSize) bytes)")
            } else {
                if fileExists && fileSize <= 4096 {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }
    
    func removeAllTaps() {
        for engine in trackedEngines.allObjects {
            engine.outputNode.removeTap(onBus: 0)
        }
        tapLock.lock()
        installedTaps.removeAllObjects()
        currentFile = nil
        currentCaptureURI = nil
        tapLock.unlock()
    }
}

struct AudioCaptureHookGroup: HookGroup {}

class AVAudioEngineStartHook: ClassHook<AVAudioEngine> {
    typealias Group = AudioCaptureHookGroup
    
    func start() throws {
        trackedEngines.add(target)
        AudioCaptureManager.shared.installTapIfNeeded(on: target)
        try orig.start()
    }
    
    func stop() {
        AudioCaptureManager.shared.removeTap(from: target)
        orig.stop()
    }
}

class AVAudioEngineInitHook: ClassHook<NSObject> {
    typealias Group = AudioCaptureHookGroup
    static let targetName = "AVAudioEngine"
    
    func init() -> Any {
        let engine = orig.init() as! AVAudioEngine
        trackedEngines.add(engine)
        return engine
    }
}
