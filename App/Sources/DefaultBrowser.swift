import PadCore
import SwiftUI
import UIKit

/// Whether Safience is the default browser, as iPadOS tells it, and the way
/// to Settings to make it so.
///
/// iPadOS answers only so often (UIApplication.isDefault(_:) is rate-limited
/// and throws when asked too soon), so the last answer is kept and shown
/// until it may be asked again.
@MainActor
final class DefaultBrowser: ObservableObject {
    static let shared = DefaultBrowser()

    enum Status: String {
        case unknown, isDefault, notDefault
    }

    @Published private(set) var status: Status

    private static let key = "defaultBrowserStatus"

    private init() {
        status = UserDefaults.standard.string(forKey: Self.key).flatMap(Status.init(rawValue:)) ?? .unknown
    }

    /// Asks iPadOS again, keeping the last answer when it won't say.
    func refresh() {
        guard #available(iOS 18.2, *) else { status = .unknown; return }
        do {
            status = try UIApplication.shared.isDefault(.webBrowser) ? .isDefault : .notDefault
            UserDefaults.standard.set(status.rawValue, forKey: Self.key)
        } catch {
            // Rate-limited, or not known on this iPad: the last answer stands.
        }
    }

    var instructions: String {
        let steps: String
        if #available(iOS 18.3, *) { steps = "In Settings, open Browser App and choose Safience." }
        else { steps = "In Settings, open Default Browser App and choose Safience." }
        guard status == .unknown else { return steps }
        if #available(iOS 18.2, *) { return "The current default browser could not be confirmed. " + steps }
        return "This version of iOS does not report the current default browser. " + steps
    }

    /// Settings › Apps › Default Apps where iPadOS has it (18.3 and later),
    /// otherwise the app's own page in Settings.
    func openSettings() {
        var page = UIApplication.openSettingsURLString
        if #available(iOS 18.3, *) { page = UIApplication.openDefaultApplicationsSettingsURLString }
        guard let url = URL(string: page) else { return }
        UIApplication.shared.open(url)
    }
}

/// Settings' first section: Safience as the default browser.
struct DefaultBrowserSection: View {
    @ObservedObject var browser = DefaultBrowser.shared
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Section {
            if browser.status == .isDefault {
                Label("Safience is your default browser", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            } else {
                Button(browser.status == .unknown ? "Check Default Browser in Settings…" : "Make Safience the Default Browser…") { browser.openSettings() }
            }
        } header: {
            SettingsHeader("Default browser", .defaultBrowser)
        } footer: {
            // The step the button leaves to do, and nothing once it is done.
            if browser.status != .isDefault {
                Text(browser.instructions)
            }
        }
        .onAppear { browser.refresh() }
        .onChange(of: phase) { _, next in if next == .active { browser.refresh() } }
    }
}
