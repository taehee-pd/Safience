import Foundation

/// Ads and trackers, blocked by WebKit's own content blocker: filter lists in
/// Adblock Plus's syntax (EasyList, EasyPrivacy) turned into the JSON rules a
/// WKContentRuleList compiles. WebKit does the blocking itself, before a
/// request is made and in its own processes; nothing runs in the page.
///
/// WebKit's rules say less than the lists do. A url-filter is a regular
/// expression without alternatives (a|b), counted repeats (a{2}) or classes
/// (\d), in ASCII only; a trigger has if-domain or unless-domain, never both;
/// an exception (ignore-previous-rules) undoes only the rules before it in its
/// own list; and one selector WebKit can't parse fails the whole list. So a
/// filter WebKit can't say exactly is left out rather than said loosely, and
/// hiding goes in lists of its own, apart from blocking (ContentBlocking.plan).
public struct BlockingRule: Encodable, Equatable, Sendable {
    public struct Trigger: Encodable, Equatable, Sendable {
        public var urlFilter: String
        public var caseSensitive: Bool?
        public var resourceType: [String]?
        public var loadType: [String]?
        public var loadContext: [String]?
        public var ifDomain: [String]?
        public var unlessDomain: [String]?

        public init(urlFilter: String = ".*", caseSensitive: Bool? = nil, resourceType: [String]? = nil,
                    loadType: [String]? = nil, loadContext: [String]? = nil, ifDomain: [String]? = nil,
                    unlessDomain: [String]? = nil) {
            self.urlFilter = urlFilter
            self.caseSensitive = caseSensitive
            self.resourceType = resourceType
            self.loadType = loadType
            self.loadContext = loadContext
            self.ifDomain = ifDomain
            self.unlessDomain = unlessDomain
        }

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case caseSensitive = "url-filter-is-case-sensitive"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case loadContext = "load-context"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
        }
    }

    public struct Action: Encodable, Equatable, Sendable {
        public var type: String
        public var selector: String?

        public static let block = Action(type: "block")
        public static let allow = Action(type: "ignore-previous-rules")
        public static func hide(_ selector: String) -> Action { Action(type: "css-display-none", selector: selector) }
    }

    public var trigger: Trigger
    public var action: Action

    public init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }
}

/// One filter list, converted.
public struct FilterRules: Equatable, Sendable {
    /// Blocking, then the exceptions to it, then the blocking marked
    /// $important, which exceptions don't undo: the order a list needs.
    public var blocks: [BlockingRule] = []
    public var exceptions: [BlockingRule] = []
    public var important: [BlockingRule] = []
    /// Element hiding (css-display-none), already grouped.
    public var hiding: [BlockingRule] = []
    /// Filters WebKit can't say exactly, and so left out.
    public var skipped = 0
    /// The list's "! Version:", and how long it says it stays fresh ("! Expires:").
    public var version: String?
    public var expires: TimeInterval?

    public init() {}

    public var network: [BlockingRule] { blocks + exceptions + important }
    public var count: Int { blocks.count + exceptions.count + important.count + hiding.count }
}

/// One rule list for WebKit to compile: its identifier, which changes when
/// what it holds does, its JSON, and how many rules it has.
public struct PlannedList: Equatable, Sendable {
    public let id: String
    public let json: String
    public let rules: Int
}

/// A filter list Safience uses: what it is called, where it comes from, and
/// whose it is (shown in Settings, as its licence asks).
public struct FilterList: Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
}

public enum ContentBlocking {
    /// The lists, both by the EasyList authors (easylist.to), under GPLv3 or
    /// CC BY-SA 3.0 or later; Safience uses them under CC BY-SA (Filters/LICENSE.md).
    public static let lists: [FilterList] = [
        ("easylist", "EasyList", "https://easylist.to/easylist/easylist.txt"),
        ("easyprivacy", "EasyPrivacy", "https://easylist.to/easylist/easyprivacy.txt"),
    ].compactMap { id, name, address in URL(string: address).map { FilterList(id: id, name: name, url: $0) } }

    public static let credit = "EasyList and EasyPrivacy, by the EasyList authors (easylist.to), under CC BY-SA"

    /// Moves on when the conversion changes, so lists compiled by an older
    /// one are made again.
    public static let converterVersion = 1
    /// WebKit's limit for one list (an Apple engineer on the developer forums, thread 734111).
    public static let rulesPerList = 150_000
    /// Hiding in lists of this many rules: a selector WebKit turns down then
    /// costs one of them, not all of the hiding.
    public static let hidingPerList = 1_000
    /// The least time between two downloads of a list, whatever it says.
    public static let shortestRefresh: TimeInterval = 4 * 24 * 60 * 60

    /// The list as it ships inside the app, for the first launch and for
    /// when no download has worked yet.
    public static func bundled(_ list: FilterList) -> String? {
        guard let url = Bundle.module.url(forResource: list.id, withExtension: "txt", subdirectory: "Filters") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// What WebKit compiles, list by list, for the lists' texts: blocking in
    /// one list when it fits, so one list's exceptions reach the other's
    /// blocking; hiding in lists of `hidingPerList`. Each comes with an
    /// identifier that changes when what it holds does.
    public static func plan(_ converted: [FilterRules]) -> [PlannedList] {
        let versions = converted.map { $0.version ?? "?" }.joined(separator: "+")
        let stamp = "v\(converterVersion)-\(stableHash(versions))"
        var groups: [[BlockingRule]] = []
        let merged = network(converted)
        if merged.count <= rulesPerList {
            groups.append(merged)
        } else {
            // One list each; one still too long keeps its exceptions and
            // the rule after them, and loses blocking from its end.
            for rules in converted {
                var fitted = rules
                let room = rulesPerList - rules.exceptions.count - rules.important.count - 1
                fitted.blocks = Array(rules.blocks.prefix(max(0, room)))
                groups.append(network([fitted]))
            }
        }
        var out: [PlannedList] = []
        for (index, rules) in groups.enumerated() where !rules.isEmpty {
            out.append(PlannedList(id: "blocking.\(stamp).network.\(index)", json: json(rules), rules: rules.count))
        }
        let hiding = converted.flatMap(\.hiding)
        for start in stride(from: 0, to: hiding.count, by: hidingPerList) {
            let rules = Array(hiding[start..<min(start + hidingPerList, hiding.count)])
            out.append(PlannedList(id: "blocking.\(stamp).hiding.\(start / hidingPerList)", json: json(rules), rules: rules.count))
        }
        return out
    }

    /// All the lists' blocking, then all their exceptions, then $important,
    /// and last a rule that lets every page itself load: a filter blocks what
    /// a page loads, never the page you went to (Adblock Plus's own rule).
    public static func network(_ converted: [FilterRules]) -> [BlockingRule] {
        var rules = converted.flatMap(\.blocks) + converted.flatMap(\.exceptions) + converted.flatMap(\.important)
        guard !rules.isEmpty else { return [] }
        rules.append(BlockingRule(trigger: .init(resourceType: ["document"], loadContext: ["top-frame"]), action: .allow))
        return rules
    }

    public static func json(_ rules: [BlockingRule]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// FNV-1a: the same everywhere and every run, unlike Hasher.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 36)
    }
}

/// Adblock Plus syntax to WebKit's rules (ContentBlocking).
public enum FilterConverter {
    public static let selectorsPerRule = 50

    public static func convert(_ text: String) -> FilterRules {
        var out = FilterRules()
        var networkLines: [String] = []
        var hidingLines: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("[") { continue }
            if line.hasPrefix("!") {
                header(line, into: &out)
                continue
            }
            if let kind = cosmeticKind(line) {
                if kind == .plain { hidingLines.append(line) } else { out.skipped += 1 }
            } else {
                networkLines.append(line)
            }
        }

        // $badfilter turns off the filter it names, wherever it is.
        var turnedOff = Set<String>()
        for line in networkLines {
            if let named = withoutBadfilter(line) { turnedOff.insert(named) }
        }
        var hide = HidingBuilder()
        for line in networkLines {
            if turnedOff.contains(line) || withoutBadfilter(line) != nil {
                out.skipped += 1
                continue
            }
            guard let filter = NetworkFilter(line) else {
                out.skipped += 1
                continue
            }
            switch filter.kind {
            case .elemhideException(let domain):
                hide.noHiding.insert(domain)
            case .generichideException(let domain):
                hide.noGenericHiding.insert(domain)
            case .rules(let rules):
                if filter.exception {
                    out.exceptions += rules
                } else if filter.important {
                    out.important += rules
                } else {
                    out.blocks += rules
                }
            }
        }
        for line in hidingLines where !hide.add(line) { out.skipped += 1 }
        out.hiding = hide.rules()
        return out
    }

    // MARK: The list's header

    static func header(_ line: String, into out: inout FilterRules) {
        let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("version:") {
            out.version = text.dropFirst("version:".count).trimmingCharacters(in: .whitespaces)
        } else if text.lowercased().hasPrefix("expires:") {
            // "4 days (update frequency)", "12 hours".
            let words = text.dropFirst("expires:".count).split(separator: " ")
            guard let first = words.first, let number = Double(first) else { return }
            let unit = words.count > 1 ? words[1].lowercased() : "days"
            out.expires = number * (unit.hasPrefix("hour") ? 3600 : 86400)
        }
    }

    // MARK: Telling hiding from blocking

    enum CosmeticKind { case plain, other }

    /// "##" and "#@#" are hiding WebKit can do; "#?#", "#$#", "#%#" and
    /// their exceptions are procedural filters, styles and scripts it can't,
    /// and so are "$$" and "##+js(…)" and "##^…" (HTML filtering).
    static func cosmeticKind(_ line: String) -> CosmeticKind? {
        if line.contains("$$") || line.contains("$@$") { return .other }
        guard let hash = line.range(of: "#") else { return nil }
        let rest = line[hash.lowerBound...]
        for marker in ["#?#", "#$#", "#%#", "#@?#", "#@$#", "#@%#"] where rest.contains(marker) { return .other }
        guard let separator = line.range(of: "#@#") ?? line.range(of: "##") else { return nil }
        let selector = line[separator.upperBound...]
        if selector.hasPrefix("+js(") || selector.hasPrefix("^") { return .other }
        return .plain
    }

    static func withoutBadfilter(_ line: String) -> String? {
        guard let dollar = line.lastIndex(of: "$") else { return nil }
        let options = line[line.index(after: dollar)...].split(separator: ",").map(String.init)
        guard options.contains("badfilter") else { return nil }
        let kept = options.filter { $0 != "badfilter" }
        return String(line[..<dollar]) + (kept.isEmpty ? "" : "$" + kept.joined(separator: ","))
    }
}

// MARK: Blocking filters

/// One blocking filter or exception: `||ads.example.com^$third-party`,
/// `@@||example.com/ads.js$script,domain=example.com`, `/banner/*/img^`.
struct NetworkFilter {
    enum Kind {
        case rules([BlockingRule])
        /// @@||example.com^$elemhide: no hiding at all on that site.
        case elemhideException(String)
        /// @@||example.com^$generichide: no hiding but that site's own.
        case generichideException(String)
    }

    let kind: Kind
    let exception: Bool
    let important: Bool

    /// The resource types WebKit has, as the lists name them. `other` is
    /// WebKit's "raw" (fetch, XHR and loads with no type), which every
    /// version Safience runs on knows.
    static let types: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet",
        "font": "font", "media": "media", "xmlhttprequest": "raw", "xhr": "raw", "other": "raw",
        "websocket": "websocket", "ping": "ping", "beacon": "ping",
    ]
    static let allTypes = Array(Set(types.values)).sorted()

    /// Options that change nothing WebKit can be told, or that ask for
    /// something it can't do: a filter with one of these is left out.
    static let unsupported: Set<String> = [
        "popup", "genericblock", "specifichide", "shide", "csp", "redirect", "redirect-rule", "removeparam",
        "queryprune", "rewrite", "header", "permissions", "replace", "urltransform", "denyallow", "to", "method",
        "cname", "sitekey", "strict1p", "strict3p", "webrtc", "inline-script", "inline-font", "empty", "mp4",
        "network", "app", "extension", "content", "jsinject", "urlblock", "stealth", "cookie", "hls", "jsonprune",
        "referrerpolicy", "ipaddress", "reason", "urlskip", "object", "object-subrequest",
    ]
    static let known: Set<String> = unsupported.union(types.keys).union([
        "third-party", "3p", "first-party", "1p", "domain", "from", "match-case", "important", "badfilter",
        "subdocument", "frame", "document", "doc", "elemhide", "ehide", "generichide", "ghide", "all",
    ])

    init?(_ line: String) {
        var body = Substring(line)
        exception = body.hasPrefix("@@")
        if exception { body = body.dropFirst(2) }
        var options: [String] = []
        if let dollar = body.lastIndex(of: "$") {
            let tail = body[body.index(after: dollar)...]
            let first = tail.prefix { $0 != "," && $0 != "=" }
            let name = first.hasPrefix("~") ? String(first.dropFirst()) : String(first)
            if NetworkFilter.known.contains(name) {
                options = tail.split(separator: ",").map(String.init)
                body = body[..<dollar]
            }
        }

        var resourceTypes = Set<String>()
        var notTypes = Set<String>()
        var frames = false
        var notFrames = false
        var party: String?
        var include: [String] = []
        var exclude: [String] = []
        var caseSensitive = false
        var isImportant = false
        var document = false
        var elemhide = false
        var generichide = false
        var droppedTypes = false
        for option in options {
            let negated = option.hasPrefix("~")
            let plain = negated ? String(option.dropFirst()) : option
            let parts = plain.split(separator: "=", maxSplits: 1).map(String.init)
            guard let name = parts.first else { continue }
            let value = parts.count > 1 ? parts[1] : ""
            if NetworkFilter.unsupported.contains(name) {
                // Leaving out a type WebKit lacks ("object") is fine; asking for it alone is not.
                if name == "object" || name == "object-subrequest" {
                    droppedTypes = true
                    continue
                }
                return nil
            }
            switch name {
            case "third-party", "3p": party = negated ? "first-party" : "third-party"
            case "first-party", "1p": party = negated ? "third-party" : "first-party"
            case "domain", "from":
                // "*example.com": the site and its subdomains, as the lists mean it.
                for entry in value.split(separator: "|") {
                    let excluded = entry.hasPrefix("~")
                    guard let domain = Domains.webKit(excluded ? String(entry.dropFirst()) : String(entry)) else { continue }
                    if excluded { exclude.append("*" + domain) } else { include.append("*" + domain) }
                }
                if include.isEmpty && exclude.isEmpty { return nil }
            case "match-case": caseSensitive = !negated
            case "important": isImportant = true
            case "subdocument", "frame": if negated { notFrames = true } else { frames = true }
            case "document", "doc": if negated { continue } else { document = true }
            case "elemhide", "ehide": elemhide = true
            case "generichide", "ghide": generichide = true
            case "all": continue
            case "badfilter": return nil
            default:
                guard let type = NetworkFilter.types[name] else { return nil }
                if negated { notTypes.insert(type) } else { resourceTypes.insert(type) }
            }
        }
        important = isImportant
        // One trigger can't say "on this site but not that part of it".
        if !include.isEmpty && !exclude.isEmpty { return nil }

        // Exceptions for a whole site: no blocking, or no hiding, on it.
        if exception && (document || elemhide || generichide) {
            guard let site = NetworkFilter.siteOnly(body) else { return nil }
            if document {
                kind = .rules([BlockingRule(trigger: .init(ifDomain: ["*" + site]), action: .allow)])
            } else if elemhide {
                kind = .elemhideException(site)
            } else {
                kind = .generichideException(site)
            }
            return
        }
        // Blocking a page you went to isn't done (ContentBlocking.network).
        if document || elemhide || generichide { return nil }

        guard let urlFilters = NetworkFilter.urlFilters(body) else { return nil }
        if !notTypes.isEmpty && resourceTypes.isEmpty {
            resourceTypes = Set(NetworkFilter.allTypes).subtracting(notTypes)
            if !notFrames { frames = true }
        }
        if droppedTypes && resourceTypes.isEmpty && !frames { return nil }
        let action: BlockingRule.Action = exception ? .allow : .block
        var rules: [BlockingRule] = []
        for urlFilter in urlFilters {
            var trigger = BlockingRule.Trigger(urlFilter: urlFilter)
            if caseSensitive { trigger.caseSensitive = true }
            if let party { trigger.loadType = [party] }
            if !include.isEmpty { trigger.ifDomain = include.sorted() }
            if !exclude.isEmpty { trigger.unlessDomain = exclude.sorted() }
            var made = 0
            if !resourceTypes.isEmpty {
                var typed = trigger
                typed.resourceType = resourceTypes.sorted()
                rules.append(BlockingRule(trigger: typed, action: action))
                made += 1
            }
            if frames {
                // A frame is a document loaded inside the page.
                var framed = trigger
                framed.resourceType = ["document"]
                framed.loadContext = ["child-frame"]
                rules.append(BlockingRule(trigger: framed, action: action))
                made += 1
            }
            if made == 0 {
                if notFrames { trigger.resourceType = NetworkFilter.allTypes }
                rules.append(BlockingRule(trigger: trigger, action: action))
            }
        }
        kind = .rules(rules)
    }

    /// "||example.com^" or "||example.com": the site, for a whole-site exception.
    static func siteOnly(_ body: Substring) -> String? {
        guard body.hasPrefix("||") else { return nil }
        var host = body.dropFirst(2)
        if host.hasSuffix("^") { host = host.dropLast() }
        return Domains.webKit(String(host))
    }

    /// The filter's address pattern as WebKit's url-filters (one, or two
    /// where it ends in a separator that may be the end of the address), or
    /// nil where WebKit can't say it.
    static func urlFilters(_ body: Substring) -> [String]? {
        if body.count > 2, body.hasPrefix("/"), body.hasSuffix("/") {
            return regex(String(body.dropFirst().dropLast())).map { [$0] }
        }
        var pattern = body
        var out = ""
        let hostAnchor = pattern.hasPrefix("||")
        if hostAnchor {
            // Any scheme, the host or one of its subdomains.
            out = "^[a-z][a-z0-9.+-]*://([^/:]*\\.)?"
            pattern = pattern.dropFirst(2)
        } else if pattern.hasPrefix("|") {
            out = "^"
            pattern = pattern.dropFirst()
        }
        var endAnchor = false
        if pattern.hasSuffix("|") {
            endAnchor = true
            pattern = pattern.dropLast()
        }
        while pattern.hasPrefix("*") && out.isEmpty { pattern = pattern.dropFirst() }
        while pattern.hasSuffix("*") && !endAnchor { pattern = pattern.dropLast() }
        if pattern.isEmpty { return out.isEmpty ? [".*"] : nil }
        // A separator: any character but a letter, a digit or _ - . %, or the end.
        let separator = "[^a-zA-Z0-9_.%-]"
        let characters = Array(pattern)
        var lastSeparator = false
        for (index, character) in characters.enumerated() {
            guard character.isASCII, let ascii = character.asciiValue, ascii >= 0x21, ascii < 0x7f else { return nil }
            switch character {
            case "*":
                out += ".*"
            case "^":
                if index == characters.count - 1 && !endAnchor {
                    lastSeparator = true
                } else {
                    out += separator
                }
            case ".", "+", "?", "(", ")", "[", "]", "{", "}", "\\", "|", "$":
                out += "\\" + String(character)
            default:
                out.append(character)
            }
        }
        if endAnchor { out += "$" }
        guard lastSeparator else { return [out] }
        // A host is always followed by its path or its port in the address
        // WebKit matches ("https://ads.test/"), so there the end needn't be
        // asked for. Elsewhere, a separator or the end is two rules: WebKit
        // has no "or", and "(separator.*)?$" takes it twenty times as long
        // to compile.
        if hostAnchor && !characters.dropLast().contains(where: { "/^*?=&:".contains($0) }) {
            return [out + "[/:]"]
        }
        return [out + separator, out + "$"]
    }

    /// A /regular expression/ filter, if it is in the part of the syntax
    /// WebKit takes: literal ASCII, escapes of punctuation, . * + ?, [sets],
    /// (groups) and the anchors. Alternatives, counted repeats, classes such
    /// as \d, and (?…) aren't.
    static func regex(_ pattern: String) -> String? {
        guard !pattern.isEmpty, pattern.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else { return nil }
        let characters = Array(pattern)
        var depth = 0
        var inSet = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\":
                guard index + 1 < characters.count else { return nil }
                let next = characters[index + 1]
                if next.isLetter || next.isNumber { return nil }
                index += 1
            case "|", "{", "}":
                if !inSet { return nil }
            case "[":
                if inSet { return nil }
                inSet = true
            case "]":
                if inSet { inSet = false }
            case "(":
                if inSet { break }
                if index + 1 < characters.count && characters[index + 1] == "?" { return nil }
                depth += 1
            case ")":
                if inSet { break }
                depth -= 1
                if depth < 0 { return nil }
            case "^":
                if !inSet && index != 0 { return nil }
            case "$":
                if !inSet && index != characters.count - 1 { return nil }
            default:
                break
            }
            index += 1
        }
        return depth == 0 && !inSet ? pattern : nil
    }
}

// MARK: Element hiding

/// `##.ad-banner` on every site, `example.com##.ad` on one, `example.com#@#.ad`
/// not there: grouped into rules of `FilterConverter.selectorsPerRule`.
struct HidingBuilder {
    /// Sites with no hiding at all ($elemhide), or none but their own ($generichide).
    var noHiding = Set<String>()
    var noGenericHiding = Set<String>()

    private var generic: [String] = []
    private var genericSeen = Set<String>()
    private var genericExceptions: [String: Set<String>] = [:]
    private var genericNowhere = Set<String>()
    private var specific: [String: (domains: [String], selectors: [String])] = [:]
    private var specificOrder: [String] = []

    /// False for a line it leaves out.
    mutating func add(_ line: String) -> Bool {
        let isException: Bool
        let separator: Range<String.Index>
        if let at = line.range(of: "#@#") {
            isException = true
            separator = at
        } else if let at = line.range(of: "##") {
            isException = false
            separator = at
        } else {
            return false
        }
        let selector = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard Selectors.isSafe(selector) else { return false }
        var include: [String] = []
        var exclude: [String] = []
        let domainText = line[..<separator.lowerBound]
        if !domainText.isEmpty {
            for entry in domainText.split(separator: ",") {
                let excluded = entry.hasPrefix("~")
                guard let domain = Domains.webKit(excluded ? String(entry.dropFirst()) : String(entry)) else { continue }
                if excluded { exclude.append(domain) } else { include.append(domain) }
            }
            if include.isEmpty && exclude.isEmpty { return false }
        }
        if isException {
            if include.isEmpty {
                // Not hidden anywhere after all.
                genericNowhere.insert(selector)
            } else {
                genericExceptions[selector, default: []].formUnion(include)
            }
            return true
        }
        if include.isEmpty {
            if !exclude.isEmpty { genericExceptions[selector, default: []].formUnion(exclude) }
            if genericSeen.insert(selector).inserted { generic.append(selector) }
        } else {
            // A site's own hiding; "on these but not those" says "on these".
            let key = include.sorted().joined(separator: ",")
            if specific[key] == nil {
                specific[key] = (include.sorted(), [])
                specificOrder.append(key)
            }
            specific[key]?.selectors.append(selector)
        }
        return true
    }

    func rules() -> [BlockingRule] {
        var out: [BlockingRule] = []
        let noGeneric = noHiding.union(noGenericHiding).map { "*" + $0 }.sorted()
        var plain: [String] = []
        for selector in generic where !genericNowhere.contains(selector) {
            if let except = genericExceptions[selector] {
                let unless = Set(except.map { "*" + $0 }).union(noGeneric).sorted()
                out.append(BlockingRule(trigger: .init(unlessDomain: unless), action: .hide(selector)))
            } else {
                plain.append(selector)
            }
        }
        for group in Self.chunks(plain) {
            out.append(BlockingRule(trigger: .init(unlessDomain: noGeneric.isEmpty ? nil : noGeneric),
                                    action: .hide(group.joined(separator: ", "))))
        }
        for key in specificOrder {
            guard let entry = specific[key] else { continue }
            let domains = entry.domains.filter { !noHiding.contains($0) }.map { "*" + $0 }
            guard !domains.isEmpty else { continue }
            var seen = Set<String>()
            let selectors = entry.selectors.filter { selector in
                // Excepted on one of its sites: left out on all, rather than hidden where it shouldn't be.
                if let except = genericExceptions[selector], !except.isDisjoint(with: entry.domains) { return false }
                return seen.insert(selector).inserted
            }
            for group in Self.chunks(selectors) {
                out.append(BlockingRule(trigger: .init(ifDomain: domains), action: .hide(group.joined(separator: ", "))))
            }
        }
        return out
    }

    static func chunks(_ list: [String]) -> [[String]] {
        stride(from: 0, to: list.count, by: FilterConverter.selectorsPerRule).map {
            Array(list[$0..<min($0 + FilterConverter.selectorsPerRule, list.count)])
        }
    }
}

enum Domains {
    /// A domain as WebKit's if-domain and unless-domain take it: lower case
    /// ASCII, no wildcard TLD ("example.*") and nothing that isn't a host.
    static func webKit(_ text: String) -> String? {
        let domain = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !domain.isEmpty, !domain.hasPrefix("."), !domain.hasSuffix("."),
              domain.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." || $0 == "-" || $0 == "_" })
        else { return nil }
        return domain
    }
}

enum Selectors {
    /// The pseudo-classes WebKit's CSS parser knows, of those filter lists use.
    static let pseudoClasses: Set<String> = [
        "not", "has", "is", "where", "nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type",
        "first-child", "last-child", "only-child", "first-of-type", "last-of-type", "only-of-type", "empty",
        "root", "checked", "disabled", "enabled", "link", "any-link", "target", "lang", "dir", "optional",
        "required", "read-only", "read-write", "placeholder-shown", "default", "indeterminate", "valid",
        "invalid", "in-range", "out-of-range", "defined", "scope", "visited",
    ]

    /// A selector WebKit will parse. One it won't fails the whole list, so
    /// anything unsure is turned down: procedural filters (:-abp-has,
    /// :has-text, :xpath…), pseudo-elements, unbalanced brackets or quotes,
    /// anything outside plain ASCII, and :has inside :has.
    static func isSafe(_ selector: String) -> Bool {
        guard !selector.isEmpty, selector.count < 2_000,
              selector.allSatisfy({ $0.isASCII && ($0 == " " || !$0.isWhitespace) }) else { return false }
        if selector.contains("{") || selector.contains("}") || selector.contains(";") || selector.contains("!") {
            return false
        }
        if selector.components(separatedBy: ":has(").count > 2 { return false }
        let characters = Array(selector)
        var parens = 0
        var brackets = 0
        var quote: Character?
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if let open = quote {
                if character == "\\" { index += 2; continue }
                if character == open { quote = nil }
                index += 1
                continue
            }
            switch character {
            case "\\":
                // An escape needs something to escape.
                if index + 1 >= characters.count { return false }
                index += 2
                continue
            case "\"", "'":
                quote = character
            case "[":
                brackets += 1
            case "]":
                brackets -= 1
                if brackets < 0 { return false }
            case "(":
                parens += 1
            case ")":
                parens -= 1
                if parens < 0 { return false }
            case ":" where brackets == 0:
                if index + 1 < characters.count && characters[index + 1] == ":" { return false }
                var end = index + 1
                while end < characters.count, characters[end].isLetter || characters[end] == "-" { end += 1 }
                let name = String(characters[(index + 1)..<end]).lowercased()
                guard pseudoClasses.contains(name) else { return false }
                index = end
                continue
            default:
                break
            }
            index += 1
        }
        return parens == 0 && brackets == 0 && quote == nil
    }
}
