import Foundation
#if canImport(Compression)
import Compression
#endif

/// Just enough of the ZIP format to take one file out of an archive: the
/// one Safari saves when it exports its browsing data (Settings › Apps ›
/// Safari › Export), with Bookmarks.html inside. Stored and deflated files;
/// not encrypted ones, not ZIP64. Apple's Compression framework inflates,
/// so nothing beyond Apple's frameworks is needed; where it isn't (Linux),
/// only stored files come out.
public enum ZipFile {
    /// Whether `data` starts the way a ZIP archive does.
    public static func isArchive(_ data: Data) -> Bool {
        data.count >= 4 && [UInt8](data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04]
    }

    /// The names of the files in the archive, folders included.
    public static func names(in data: Data) -> [String] {
        entries(in: [UInt8](data)).map(\.name)
    }

    /// The first file whose name passes `matching`, unpacked; nil when there
    /// is none, or it can't be unpacked here.
    public static func file(in data: Data, matching: (String) -> Bool) -> Data? {
        let bytes = [UInt8](data)
        guard let entry = entries(in: bytes).first(where: { matching($0.name) }) else { return nil }
        return unpack(entry, from: bytes)
    }

    /// No file in a bookmarks export comes near this; an archive that says
    /// otherwise is not read.
    static let largest = 64 * 1024 * 1024

    struct Entry {
        var name: String
        var method: UInt16
        var flags: UInt16
        var packedSize: Int
        var size: Int
        var headerOffset: Int
    }

    /// The archive's table of contents, from its end: the central directory
    /// is the part every writer gets right.
    static func entries(in bytes: [UInt8]) -> [Entry] {
        guard bytes.count >= 22 else { return [] }
        let earliest = max(0, bytes.count - 22 - 65_535)
        var end: Int?
        var index = bytes.count - 22
        while index >= earliest {
            if u32(bytes, index) == 0x0605_4B50 {
                end = index
                break
            }
            index -= 1
        }
        guard let end, let count = u16(bytes, end + 10), let start = u32(bytes, end + 16) else { return [] }
        var entries: [Entry] = []
        var at = Int(start)
        for _ in 0..<Int(count) {
            guard u32(bytes, at) == 0x0201_4B50,
                  let flags = u16(bytes, at + 8), let method = u16(bytes, at + 10),
                  let packed = u32(bytes, at + 20), let size = u32(bytes, at + 24),
                  let nameLength = u16(bytes, at + 28), let extraLength = u16(bytes, at + 30),
                  let commentLength = u16(bytes, at + 32), let offset = u32(bytes, at + 42),
                  at + 46 + Int(nameLength) <= bytes.count
            else { break }
            let name = String(decoding: bytes[(at + 46)..<(at + 46 + Int(nameLength))], as: UTF8.self)
            entries.append(Entry(name: name, method: method, flags: flags, packedSize: Int(packed),
                                 size: Int(size), headerOffset: Int(offset)))
            at += 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }
        return entries
    }

    static func unpack(_ entry: Entry, from bytes: [UInt8]) -> Data? {
        // Bit 0: encrypted.
        guard entry.flags & 1 == 0, entry.size <= largest, entry.packedSize <= bytes.count,
              u32(bytes, entry.headerOffset) == 0x0403_4B50,
              let nameLength = u16(bytes, entry.headerOffset + 26),
              let extraLength = u16(bytes, entry.headerOffset + 28)
        else { return nil }
        let start = entry.headerOffset + 30 + Int(nameLength) + Int(extraLength)
        guard start + entry.packedSize <= bytes.count else { return nil }
        let packed = Array(bytes[start..<(start + entry.packedSize)])
        switch entry.method {
        case 0:
            return Data(packed)
        case 8:
            return inflate(packed, size: entry.size)
        default:
            return nil
        }
    }

    static func inflate(_ packed: [UInt8], size: Int) -> Data? {
        #if canImport(Compression)
        guard size > 0 else { return Data() }
        var out = [UInt8](repeating: 0, count: size)
        // COMPRESSION_ZLIB is raw DEFLATE, as ZIP stores it, without zlib's header.
        let written = compression_decode_buffer(&out, size, packed, packed.count, nil, COMPRESSION_ZLIB)
        guard written == size else { return nil }
        return Data(out)
        #else
        return nil
        #endif
    }

    static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16? {
        guard at >= 0, at + 2 <= bytes.count else { return nil }
        return UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= bytes.count else { return nil }
        return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
