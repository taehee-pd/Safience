import UIKit
import WebKit

/// Each space's cookies, sign-ins and site data, in a WebKit store of its own.
///
/// Made with `WKWebsiteDataStore(forIdentifier:)` and the space's id, so a
/// space's sign-ins survive relaunches and never mix with another space's:
/// two Figma accounts, one per space, both signed in. One object per space
/// for as long as the app runs, because WebKit shares processes and caches
/// between views that are given the same store object.
@MainActor
enum Stores {
    private static var made: [UUID: WKWebsiteDataStore] = [:]
    private static let erasingKey = "stores.erasing"

    static func store(for space: UUID) -> WKWebsiteDataStore {
        if let store = made[space] { return store }
        let store = WKWebsiteDataStore(forIdentifier: space)
        made[space] = store
        return store
    }

    /// A removed space's store, and everything in it, gone. What it holds is
    /// emptied at once; the store itself WebKit won't remove while a view
    /// still holds it, so it is written down and tried again at each launch
    /// until it goes.
    static func erase(_ space: UUID) {
        if let store = made.removeValue(forKey: space) {
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        }
        var pending = Set(UserDefaults.standard.stringArray(forKey: erasingKey) ?? [])
        pending.insert(space.uuidString)
        UserDefaults.standard.set(pending.sorted(), forKey: erasingKey)
        // A moment later, once the space's views have let go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sweep() }
    }

    /// Removes the stores written down for removal. At launch, before any
    /// view holds one, and after an erase.
    static func sweep() {
        for text in UserDefaults.standard.stringArray(forKey: erasingKey) ?? [] {
            guard let id = UUID(uuidString: text), made[id] == nil else { continue }
            WKWebsiteDataStore.remove(forIdentifier: id) { error in
                guard error == nil else { return }
                Task { @MainActor in
                    let left = (UserDefaults.standard.stringArray(forKey: erasingKey) ?? []).filter { $0 != text }
                    UserDefaults.standard.set(left, forKey: erasingKey)
                }
            }
        }
    }
}

/// Pictures of frozen tabs, and what it takes to bring their page back where
/// it was (`WKWebView.interactionState`: the back and forward list and the
/// scroll position). Kept in Caches: the system may empty it, and then a
/// tab comes back without its picture, at its address.
enum Snapshots {
    static var folder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Snapshots", isDirectory: true)
    }

    private static func file(_ tab: UUID, _ kind: String) -> URL {
        folder.appendingPathComponent("\(tab.uuidString).\(kind)")
    }

    private static let queue = DispatchQueue(label: "Snapshots", qos: .utility)

    static func save(_ picture: UIImage, for tab: UUID) {
        queue.async {
            guard let data = picture.jpegData(compressionQuality: 0.7) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file(tab, "jpg"), options: .atomic)
        }
    }

    static func picture(for tab: UUID) -> UIImage? {
        UIImage(contentsOfFile: file(tab, "jpg").path)
    }

    /// The interaction state is opaque, but it is data underneath; anything
    /// else is kept in memory only.
    static func save(state: Any?, for tab: UUID) {
        guard let data = state as? Data else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file(tab, "state"), options: .atomic)
        }
    }

    static func state(for tab: UUID) -> Data? {
        try? Data(contentsOf: file(tab, "state"))
    }

    static func remove(_ tab: UUID) {
        queue.async {
            try? FileManager.default.removeItem(at: file(tab, "jpg"))
            try? FileManager.default.removeItem(at: file(tab, "state"))
        }
    }

    /// Everything for tabs that no longer exist, at launch.
    static func prune(keeping tabs: Set<UUID>) {
        queue.async {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names {
                let id = name.split(separator: ".").first.flatMap { UUID(uuidString: String($0)) }
                if let id, tabs.contains(id) { continue }
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }
}
