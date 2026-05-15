import UIKit

class URLSessionHelper {
    static let shared = URLSessionHelper()

    /// Accessed from URLSession delegate callbacks which may be concurrent.
    /// Keep all mutations synchronized to avoid races / EXC_BAD_ACCESS.
    private let queue = DispatchQueue(label: "com.eeveespotify.urlsessionhelper.requestsMap")
    private var requestsMap: [URL: Data]

    private init() {
        self.requestsMap = [:]
    }
    
    static var DarwinVersion: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let dv = String(
            bytes: Data(bytes: &sysinfo.release, count: Int(_SYS_NAMELEN)), 
            encoding: .ascii
        )!.trimmingCharacters(in: .controlCharacters)
        return "Darwin/\(dv)"
    }
    
    static var CFNetworkVersion: String {
        let dictionary = Bundle(identifier: "com.apple.CFNetwork")?.infoDictionary!
        let version = dictionary?["CFBundleShortVersionString"] as! String
        return "CFNetwork/\(version)"
    }
    
    func setOrAppend(_ data: Data, for url: URL) {
        queue.sync {
            var loadedData = requestsMap[url] ?? Data()
            loadedData.append(data)
            requestsMap[url] = loadedData
        }
    }

    func obtainData(for url: URL) -> Data? {
        queue.sync {
            requestsMap.removeValue(forKey: url)
        }
    }
}
