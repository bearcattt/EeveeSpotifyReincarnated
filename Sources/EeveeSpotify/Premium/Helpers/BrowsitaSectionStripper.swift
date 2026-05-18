import Foundation

// Strips brand-ad sections from /casita/ and /browsita/ protobuf responses.

enum BrowsitaSectionStripper {

    private static let adFieldNumbers: Set<UInt64> = [6, 7]

    static func shouldHandle(_ url: URL) -> Bool {
        let p = url.path.lowercased()
        return p.contains("/browsita/") || p.contains("/casita/")
    }

    static func strip(_ data: Data) -> Data? {
        var cursor = 0
        guard data.count >= 2, data[cursor] == 0x0a else { return nil }
        cursor += 1
        guard let (outerLen, outerLenBytes) = readVarint(data, at: cursor) else { return nil }
        cursor += outerLenBytes
        let containerStart = cursor
        let containerEnd = cursor + Int(outerLen)
        guard containerEnd <= data.count else { return nil }

        var newContainer = Data()
        var dropped = 0
        var c = containerStart

        while c < containerEnd {
            guard c < data.count, data[c] == 0x0a else { return nil }
            let sectionTagStart = c
            c += 1
            guard let (secLen, secLenBytes) = readVarint(data, at: c) else { return nil }
            c += secLenBytes
            let sectionContentStart = c
            let sectionContentEnd = c + Int(secLen)
            guard sectionContentEnd <= containerEnd else { return nil }

            if sectionContainsAdField(data, start: sectionContentStart, end: sectionContentEnd) {
                dropped += 1
            } else {
                newContainer.append(data.subdata(in: sectionTagStart..<sectionContentEnd))
            }
            c = sectionContentEnd
        }

        guard dropped > 0 else { return nil }

        var result = Data()
        result.append(0x0a)
        result.append(encodeVarint(UInt64(newContainer.count)))
        result.append(newContainer)
        if containerEnd < data.count {
            result.append(data.subdata(in: containerEnd..<data.count))
        }
        return result
    }

    private static func sectionContainsAdField(_ data: Data, start: Int, end: Int) -> Bool {
        var c = start
        while c < end {
            guard let (tag, tagBytes) = readVarint(data, at: c) else { return false }
            c += tagBytes
            let fieldNum = tag >> 3
            let wire = tag & 7
            if adFieldNumbers.contains(fieldNum) { return true }
            switch wire {
            case 0:
                guard let (_, vb) = readVarint(data, at: c) else { return false }
                c += vb
            case 1: c += 8
            case 2:
                guard let (len, lb) = readVarint(data, at: c) else { return false }
                c += lb + Int(len)
            case 5: c += 4
            default: return false
            }
            if c > end { return false }
        }
        return false
    }

    private static func readVarint(_ data: Data, at: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        var idx = at
        while idx < data.count && bytesRead < 10 {
            let b = data[idx]
            value |= UInt64(b & 0x7f) << shift
            shift += 7
            bytesRead += 1
            idx += 1
            if (b & 0x80) == 0 { return (value, bytesRead) }
        }
        return nil
    }

    private static func encodeVarint(_ v: UInt64) -> Data {
        var value = v
        var result = Data()
        while value >= 0x80 {
            result.append(UInt8((value & 0x7f) | 0x80))
            value >>= 7
        }
        result.append(UInt8(value))
        return result
    }
}
