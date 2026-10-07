import Compression
import Foundation
import PadCore
import SwiftUI
import UIKit

/// Spaces and their bookmarks in iCloud, when Settings turns it on.
///
/// iCloud's key-value store, one value per space ("space." and its iCloud
/// id), each the space's name, colour, icon and bookmarks (CloudSpace),
/// compressed. Nothing else goes: tabs, sign-ins and site data stay on each
/// device. The store keeps a megabyte in all, which holds many thousands of
/// bookmarks; past it iCloud refuses, and Settings says so.
///
/// A change here is written at once; a change from another device is taken
/// up when iCloud says it came (CloudSync, in PadCore, has the rules).
@MainActor
final class Sync: ObservableObject {
    static let shared = Sync()

    /// Something Settings should say: iCloud full, or not signed in.
    @Published private(set) var problem: String?

    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private var running = false
    /// Turned on, waiting for what iCloud already has before joining it, so
    /// a new device's spaces join the ones with their names instead of
    /// coming in beside them.
    private var joining = false
    /// Taking up what came in: what that changes here isn't written back.
    private var applying = false

    private static let prefix = "space."

    /// Spaces made now get their iCloud id at once; not while joining,
    /// when a space's name is what joins it to iCloud's.
    var assigns: Bool {
        running && !joining
    }

    var signedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// At launch with sync on, or when Settings turns it on (`join`).
    func start(join: Bool) {
        guard !running else { return }
        running = true
        problem = signedIn ? nil : "Sign in to iCloud in Settings to sync."
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: store, queue: .main) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { self?.cameIn(reason: reason, keys: keys) }
        }
        store.synchronize()
        if join {
            joining = true
            // What iCloud has may already be here; if not, it comes as the
            // first change (initial sync), or not at all on a first device.
            if !remote().isEmpty {
                finishJoining()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    guard let self, self.joining else { return }
                    self.finishJoining()
                }
            }
        } else {
            takeUp(remote())
            writeMissing()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        joining = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        problem = nil
    }

    /// After every change to the workspace here (Session.change).
    func changed(from old: Workspace, to new: Workspace) {
        guard running, !joining, !applying else { return }
        write(CloudSync.changes(from: old, to: new))
    }

    // MARK: What comes in

    private func cameIn(reason: Int?, keys: [String]) {
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            problem = "iCloud is full for Safience: it keeps up to 1 MB of spaces and bookmarks. Delete some bookmarks to sync again."
            return
        case NSUbiquitousKeyValueStoreAccountChange:
            problem = signedIn ? nil : "Sign in to iCloud in Settings to sync."
        default:
            break
        }
        if joining {
            finishJoining()
            return
        }
        let spaces = keys.filter { $0.hasPrefix(Self.prefix) }.compactMap(read)
        takeUp(spaces)
    }

    private func finishJoining() {
        joining = false
        let there = remote()
        let writes = Session.shared.change { CloudSync.join(&$0, remote: there) }
        write(writes)
    }

    /// iCloud's version of each space, here: spaces removed on another
    /// device go, with their sign-ins, unless one is the last space.
    private func takeUp(_ spaces: [CloudSpace]) {
        guard !spaces.isEmpty else { return }
        applying = true
        defer { applying = false }
        let session = Session.shared
        let removed = session.change { CloudSync.apply(spaces, to: &$0) }
        for id in removed {
            if session.workspace.spaces.count > 1 {
                session.removeSpace(id)
            } else {
                session.change { workspace in
                    if let s = workspace.spaces.firstIndex(where: { $0.id == id }) { workspace.spaces[s].cloudID = nil }
                }
            }
        }
    }

    /// Spaces synced before that iCloud doesn't have yet: made or changed
    /// while this device was offline and the app wasn't running.
    private func writeMissing() {
        var workspace = Session.shared.workspace
        CloudSync.assignIDs(&workspace)
        if workspace != Session.shared.workspace { Session.shared.change { $0 = workspace } }
        write(Session.shared.workspace.spaces.compactMap(\.cloud).filter { store.data(forKey: Self.key($0.id)) == nil })
    }

    // MARK: The store

    private func remote() -> [CloudSpace] {
        store.dictionaryRepresentation.keys.filter { $0.hasPrefix(Self.prefix) }.sorted().compactMap(read)
    }

    private func read(_ key: String) -> CloudSpace? {
        guard let packed = store.data(forKey: key), let data = Deflate.inflate(packed) else { return nil }
        return try? JSONDecoder().decode(CloudSpace.self, from: data)
    }

    private func write(_ spaces: [CloudSpace]) {
        // A full iCloud says so again if this is still too much.
        if !spaces.isEmpty, problem?.hasPrefix("iCloud is full") == true { problem = nil }
        for space in spaces {
            let key = Self.key(space.id)
            // What iCloud has already: nothing to write (and no echo).
            if read(key) == space { continue }
            guard let data = try? JSONEncoder().encode(space), let packed = Deflate.deflate(data) else { continue }
            store.set(packed, forKey: key)
        }
    }

    private static func key(_ id: UUID) -> String {
        prefix + id.uuidString
    }
}

/// zlib's raw deflate, as Apple's Compression has it.
enum Deflate {
    static func deflate(_ data: Data) -> Data? {
        // The size first, so inflate knows how much room the result needs.
        var size = UInt32(data.count).littleEndian
        var out = Data(bytes: &size, count: 4)
        // Room for data that doesn't compress: zlib adds a few bytes a block.
        let capacity = data.count + data.count / 100 + 1024
        var buffer = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(&buffer, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        out.append(contentsOf: buffer[0..<written])
        return out
    }

    static func inflate(_ data: Data) -> Data? {
        guard data.count > 4 else { return nil }
        let size = data.prefix(4).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard size > 0, size < 8_000_000 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let body = data.dropFirst(4)
        let read = body.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&buffer, size, base, body.count, nil, COMPRESSION_ZLIB)
        }
        return read == size ? Data(buffer) : nil
    }
}

/// Settings' iCloud section.
struct CloudSection: View {
    @ObservedObject var session: Session
    @ObservedObject var sync = Sync.shared

    var body: some View {
        Section {
            Toggle("Sync Spaces and Bookmarks", isOn: $session.preferences.iCloudSync)
            if session.preferences.iCloudSync, let problem = sync.problem {
                Label(problem, systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Each space's name, colour, icon and bookmarks are kept in your iCloud account and show on your other iPhones and iPads. Tabs, sign-ins and what sites store stay on each device. Turning it on joins spaces with the same name and keeps both sets of bookmarks; removing a space removes it everywhere.")
        }
    }
}
