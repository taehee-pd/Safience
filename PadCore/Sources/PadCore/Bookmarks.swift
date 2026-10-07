import Foundation

/// A space's bookmark: a link, or a folder of them. Each space has its own,
/// as it has its own sign-ins, and a new tab shows them as a grid
/// (StartPage.swift).
public struct Bookmark: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// Where it goes; nil for a folder.
    public var url: URL?
    /// What a folder holds; nil for a link.
    public var children: [Bookmark]?

    public init(id: UUID = UUID(), title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
        children = nil
    }

    public init(id: UUID = UUID(), folder title: String, children: [Bookmark]) {
        self.id = id
        self.title = title
        url = nil
        self.children = children
    }

    public var isFolder: Bool {
        url == nil
    }

    /// The name a tile shows: the title, else the address.
    public var label: String {
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty { return named }
        return url.map(Address.pretty) ?? "Folder"
    }

    /// Every link in it and in its folders.
    public var links: [Bookmark] {
        isFolder ? (children ?? []).flatMap(\.links) : [self]
    }
}

/// What bookmarks do to each other: finding, adding, taking away, merging
/// an import in.
public enum Bookmarks {
    /// Two addresses that are the same page as far as a bookmark goes: no
    /// difference for case in the scheme and host, or a slash at the end of
    /// the path. Only the path's: one at the end of a query or a fragment
    /// (?next=/a/, #/home/) is part of where the link goes.
    static func key(_ url: URL) -> String {
        var text = url.absoluteString
        if var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.percentEncodedPath.hasSuffix("/") {
            parts.percentEncodedPath.removeLast()
            text = parts.string ?? text
        }
        if let scheme = url.scheme, let host = url.host {
            let start = "\(scheme)://\(host)"
            if text.lowercased().hasPrefix(start.lowercased()) {
                text = start.lowercased() + text.dropFirst(start.count)
            }
        }
        return text
    }

    /// The bookmark for `url` at any depth, or nil.
    public static func find(_ url: URL, in items: [Bookmark]) -> Bookmark? {
        let wanted = key(url)
        for item in items {
            if let link = item.url, key(link) == wanted { return item }
            if let found = find(url, in: item.children ?? []) { return found }
        }
        return nil
    }

    /// The bookmark or folder with `id`, at any depth.
    public static func find(_ id: UUID, in items: [Bookmark]) -> Bookmark? {
        for item in items {
            if item.id == id { return item }
            if let found = find(id, in: item.children ?? []) { return found }
        }
        return nil
    }

    /// Changes the bookmark or folder with `id` in place, at any depth.
    /// False when there was none.
    @discardableResult
    public static func update(_ id: UUID, in items: inout [Bookmark], _ change: (inout Bookmark) -> Void) -> Bool {
        for index in items.indices {
            if items[index].id == id {
                change(&items[index])
                return true
            }
            guard var inside = items[index].children, update(id, in: &inside, change) else { continue }
            items[index].children = inside
            return true
        }
        return false
    }

    /// Puts `item` at the end of the folder `folder`, or of the top level
    /// for nil. False when there is no such folder.
    @discardableResult
    public static func insert(_ item: Bookmark, into folder: UUID?, of items: inout [Bookmark]) -> Bool {
        guard let folder else {
            items.append(item)
            return true
        }
        return update(folder, in: &items) { $0.children = ($0.children ?? []) + [item] } && find(folder, in: items)?.isFolder == true
    }

    /// Takes a bookmark or a folder away, at any depth. False when there was none.
    @discardableResult
    public static func remove(_ id: UUID, from items: inout [Bookmark]) -> Bool {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: index)
            return true
        }
        for index in items.indices {
            guard var inside = items[index].children, remove(id, from: &inside) else { continue }
            items[index].children = inside
            return true
        }
        return false
    }

    /// `imported` added to `existing`: a link already at its level is left
    /// out, and a folder whose name is already there is merged into that
    /// one, so importing the same file twice adds nothing. Returns how many
    /// links it added.
    @discardableResult
    public static func merge(_ imported: [Bookmark], into existing: inout [Bookmark]) -> Int {
        var added = 0
        for item in imported {
            if let link = item.url {
                guard !existing.contains(where: { $0.url.map(key) == key(link) }) else { continue }
                existing.append(Bookmark(title: item.title, url: link))
                added += 1
                continue
            }
            let children = item.children ?? []
            if let index = existing.firstIndex(where: { $0.isFolder && $0.title == item.title }) {
                var inside = existing[index].children ?? []
                added += merge(children, into: &inside)
                existing[index].children = inside
            } else {
                var inside: [Bookmark] = []
                added += merge(children, into: &inside)
                if !inside.isEmpty {
                    existing.append(Bookmark(folder: item.title, children: inside))
                }
            }
        }
        return added
    }
}

/// A site's icon is kept once for every page of the site: the host, in
/// lower case, without www.
public enum IconKey {
    public static func of(_ url: URL?) -> String? {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// What a bookmarks file holds, ready to go into a space.
public struct BookmarkImport: Equatable, Sendable {
    /// For the top of a space's bookmarks: the file's favourites first (its
    /// bookmarks bar, Safari's Favorites), then its other links and folders.
    public var items: [Bookmark]
    /// The icons the file carries, by IconKey (Chrome's export has them).
    public var icons: [String: Data]

    public var count: Int {
        items.flatMap(\.links).count
    }
}

/// The bookmarks file every browser exports, Chrome's, Safari's (on its own
/// or inside the ZIP of Safari's Export Browsing Data), Firefox's and Edge's:
/// Netscape's old format, links in nested <DL> lists under <H3> folder names.
///
/// It is read loosely, a byte at a time, because exporters never quite agree
/// and a Chrome file can be megabytes of inline icons. Only web addresses are
/// kept; javascript:, file: and browser-internal links are left out.
public enum BookmarkFile {
    public static func parse(_ data: Data) -> BookmarkImport {
        var reader = Reader(bytes: [UInt8](data))
        return reader.read()
    }

    /// Names a folder of favourites goes by: the bar under the address bar.
    static let favouriteNames: Set<String> = [
        "bookmarks bar", "bookmarks toolbar", "bookmarksbar", "favorites", "favourites",
        "favorites bar", "favourites bar", "toolbar",
    ]

    private struct Frame {
        var title: String
        var favourites: Bool
        var items: [Bookmark] = []
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0
        var frames = [Frame(title: "", favourites: false)]
        /// For each <DL> open: whether it opened a folder of its own.
        var lists: [Bool] = []
        var pending: Frame?
        var icons: [String: Data] = [:]

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func read() -> BookmarkImport {
            while let tag = nextTag() {
                switch tag.name {
                case "dl":
                    if let folder = pending {
                        frames.append(folder)
                        pending = nil
                        lists.append(true)
                    } else {
                        lists.append(false)
                    }
                case "/dl":
                    if lists.popLast() == true, frames.count > 1, let folder = frames.popLast() {
                        frames[frames.count - 1].items.append(
                            Bookmark(folder: folder.title, children: folder.items)
                        )
                        // Kept apart, to be lifted out when it is the file's favourites.
                        if folder.favourites, frames.count == 1 { favouritesIndex = frames[0].items.count - 1 }
                    }
                case "h3":
                    let title = text(until: "</h3")
                    let marked = tag.attributes["personal_toolbar_folder"]?.lowercased() == "true"
                    let named = BookmarkFile.favouriteNames.contains(title.lowercased())
                    pending = Frame(title: title, favourites: marked || (named && frames.count == 1))
                case "a":
                    let title = text(until: "</a")
                    guard let href = tag.attributes["href"], let url = URL(string: href),
                          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                          url.host != nil
                    else { break }
                    frames[frames.count - 1].items.append(Bookmark(title: title, url: url))
                    if let icon = tag.attributes["icon"], let key = IconKey.of(url), icons[key] == nil,
                       let picture = Reader.dataURL(icon) {
                        icons[key] = picture
                    }
                default:
                    break
                }
            }
            // Folders a broken file never closed.
            while frames.count > 1, let folder = frames.popLast() {
                frames[frames.count - 1].items.append(Bookmark(folder: folder.title, children: folder.items))
            }
            var items = Reader.pruned(frames[0].items)
            if let index = favouritesIndex, index < frames[0].items.count {
                let favourites = frames[0].items[index]
                let rest = frames[0].items.enumerated().filter { $0.offset != index }.map(\.element)
                items = Reader.pruned((favourites.children ?? []) + rest)
            }
            return BookmarkImport(items: items, icons: icons)
        }

        var favouritesIndex: Int?

        /// Folders with no links left in them taken out.
        static func pruned(_ items: [Bookmark]) -> [Bookmark] {
            items.compactMap { item in
                guard item.isFolder else { return item }
                let inside = pruned(item.children ?? [])
                return inside.isEmpty ? nil : Bookmark(id: item.id, folder: item.title, children: inside)
            }
        }

        // MARK: Bytes

        struct Tag {
            var name: String
            var attributes: [String: String]
        }

        /// The next tag, its name in lower case and its attributes, with the
        /// reader just past it. Comments and <!DOCTYPE> are skipped.
        mutating func nextTag() -> Tag? {
            while at < bytes.count {
                guard bytes[at] == UInt8(ascii: "<") else {
                    at += 1
                    continue
                }
                at += 1
                if starts("!--") {
                    skip(past: "-->")
                    continue
                }
                if at < bytes.count, bytes[at] == UInt8(ascii: "!") || bytes[at] == UInt8(ascii: "?") {
                    skip(past: ">")
                    continue
                }
                var name = ""
                while at < bytes.count, !Reader.isSpace(bytes[at]), bytes[at] != UInt8(ascii: ">") {
                    name.append(Character(Unicode.Scalar(Reader.lower(bytes[at]))))
                    at += 1
                }
                var attributes: [String: String] = [:]
                while at < bytes.count, bytes[at] != UInt8(ascii: ">") {
                    if Reader.isSpace(bytes[at]) || bytes[at] == UInt8(ascii: "/") {
                        at += 1
                        continue
                    }
                    let start = at
                    while at < bytes.count, !Reader.isSpace(bytes[at]), bytes[at] != UInt8(ascii: "="),
                          bytes[at] != UInt8(ascii: ">") {
                        at += 1
                    }
                    let key = String(decoding: bytes[start..<at].map(Reader.lower), as: UTF8.self)
                    while at < bytes.count, Reader.isSpace(bytes[at]) { at += 1 }
                    guard at < bytes.count, bytes[at] == UInt8(ascii: "=") else {
                        attributes[key] = ""
                        continue
                    }
                    at += 1
                    while at < bytes.count, Reader.isSpace(bytes[at]) { at += 1 }
                    var value: ArraySlice<UInt8>
                    if at < bytes.count, bytes[at] == UInt8(ascii: "\"") || bytes[at] == UInt8(ascii: "'") {
                        let quote = bytes[at]
                        at += 1
                        let from = at
                        while at < bytes.count, bytes[at] != quote { at += 1 }
                        value = bytes[from..<min(at, bytes.count)]
                        at += 1
                    } else {
                        let from = at
                        while at < bytes.count, !Reader.isSpace(bytes[at]), bytes[at] != UInt8(ascii: ">") { at += 1 }
                        value = bytes[from..<at]
                    }
                    attributes[key] = Reader.decode(String(decoding: value, as: UTF8.self))
                }
                at += 1
                return Tag(name: name, attributes: attributes)
            }
            return nil
        }

        /// The text up to a closing tag, its tags taken out, its entities
        /// decoded, its spaces tidied; the reader just past the tag.
        mutating func text(until closing: String) -> String {
            let end = Array(closing.utf8)
            let start = at
            while at < bytes.count, !matches(end, at: at) { at += 1 }
            var raw = String(decoding: bytes[start..<min(at, bytes.count)], as: UTF8.self)
            skip(past: ">")
            raw = raw.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            let words = Reader.decode(raw).split(whereSeparator: { $0.isWhitespace })
            return words.joined(separator: " ")
        }

        func matches(_ word: [UInt8], at index: Int) -> Bool {
            guard index + word.count <= bytes.count else { return false }
            for offset in word.indices where Reader.lower(bytes[index + offset]) != word[offset] {
                return false
            }
            return true
        }

        func starts(_ word: String) -> Bool {
            matches(Array(word.utf8), at: at)
        }

        mutating func skip(past word: String) {
            let wanted = Array(word.utf8)
            while at < bytes.count, !matches(wanted, at: at) { at += 1 }
            at = min(at + wanted.count, bytes.count)
        }

        static func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
        }

        static func lower(_ byte: UInt8) -> UInt8 {
            byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
        }

        /// &amp; and the rest, and numeric references.
        static func decode(_ text: String) -> String {
            guard text.contains("&") else { return text }
            let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
            var out = ""
            var rest = Substring(text)
            while let amp = rest.firstIndex(of: "&") {
                out += rest[..<amp]
                let after = rest[rest.index(after: amp)...]
                guard let semi = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semi) <= 10 else {
                    out += "&"
                    rest = after
                    continue
                }
                let name = String(after[..<semi])
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    replacement = named[name.lowercased()]
                }
                if let replacement {
                    out += replacement
                    rest = after[after.index(after: semi)...]
                } else {
                    out += "&"
                    rest = after
                }
            }
            out += rest
            return out
        }

        /// The picture in a data: URL, base64 or not.
        static func dataURL(_ text: String) -> Data? {
            guard text.lowercased().hasPrefix("data:"), let comma = text.firstIndex(of: ",") else { return nil }
            let header = text[..<comma].lowercased()
            guard header.contains("image/") else { return nil }
            let body = String(text[text.index(after: comma)...])
            if header.hasSuffix(";base64") { return Data(base64Encoded: body, options: .ignoreUnknownCharacters) }
            return body.removingPercentEncoding.map { Data($0.utf8) }
        }
    }
}
