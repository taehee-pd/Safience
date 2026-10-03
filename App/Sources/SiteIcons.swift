import PadCore
import UIKit

/// Sites' icons, for pinned tabs, tabs and bookmark tiles.
///
/// A page names its icons (bridge.js siteIcons()); the first of them that
/// loads as a picture is kept, once for the whole site, in the Caches folder,
/// and a bookmarks file's own icons (Chrome's) are kept the same way. The
/// app fetches them itself, not the page, with no cookies and nothing kept
/// by the system, and only ever takes a picture back. A site without one
/// shows its first letter (SiteIconView).
@MainActor
final class SiteIcons: ObservableObject {
    static let shared = SiteIcons()

    /// Moves on each time an icon arrives, so the views showing it look again.
    @Published private(set) var revision = 0
    private var known: [String: UIImage] = [:]
    /// Looked for on disk and not there: not looked for again this run.
    private var absent: Set<String> = []
    private var fetching: Set<String> = []

    /// The pixel size kept: sharp at 48 points, the largest the app draws.
    private static let side: CGFloat = 96

    private static var folder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Safience/SiteIcons", isDirectory: true)
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        let name = Identity.applicationName(for: ProcessInfo.processInfo.operatingSystemVersion)
        configuration.httpAdditionalHeaders = ["User-Agent": Identity.macUserAgent(applicationName: name)]
        return URLSession(configuration: configuration)
    }()

    /// The site's icon, if it has one yet.
    func image(for url: URL?) -> UIImage? {
        guard let key = IconKey.of(url) else { return nil }
        if let image = known[key] { return image }
        guard !absent.contains(key) else { return nil }
        if let file = Self.file(for: key), let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            known[key] = image
            return image
        }
        absent.insert(key)
        return nil
    }

    /// The icons a page named, best first: the first that loads as a picture
    /// is kept, unless the site has one already.
    func learn(_ candidates: [URL], for page: URL?) {
        guard let key = IconKey.of(page), image(for: page) == nil, !fetching.contains(key), !candidates.isEmpty else { return }
        fetching.insert(key)
        Task {
            defer { fetching.remove(key) }
            for candidate in candidates.prefix(6) {
                if let picture = await fetch(candidate) {
                    keep(picture, as: key)
                    return
                }
            }
        }
    }

    /// The icons a bookmarks file carried, for the sites that have none yet.
    func adopt(_ icons: [String: Data]) {
        for (key, data) in icons where known[key] == nil {
            guard let picture = UIImage(data: data), let shaped = Self.shaped(picture) else { continue }
            keep(shaped, as: key)
        }
    }

    private func fetch(_ url: URL) async -> UIImage? {
        if url.scheme?.lowercased() == "data" {
            guard let data = try? Data(contentsOf: url), let picture = UIImage(data: data) else { return nil }
            return Self.shaped(picture)
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000,
              let picture = UIImage(data: data)
        else { return nil }
        return Self.shaped(picture)
    }

    private func keep(_ picture: UIImage, as key: String) {
        known[key] = picture
        absent.remove(key)
        revision += 1
        guard let file = Self.file(for: key), let png = picture.pngData() else { return }
        let folder = Self.folder
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        }
    }

    /// Squared and scaled to the size kept; nil for a picture too small to
    /// be anything but a speck.
    private static func shaped(_ picture: UIImage) -> UIImage? {
        let size = picture.size
        guard size.width >= 16, size.height >= 16 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let scale = min(side / size.width, side / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            picture.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                    width: drawn.width, height: drawn.height))
        }
    }

    /// A host only ever becomes a file name of letters, digits, dots and dashes.
    private static func file(for key: String) -> URL? {
        guard !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        return folder.appendingPathComponent(key + ".png")
    }
}
