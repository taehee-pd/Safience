import AppKit
import PadCore
import SwiftUI

/// Shows a window before legacy files are read or copied. No browser services
/// or workspace model are created while migration is incomplete.
@MainActor
final class LaunchState: ObservableObject {
    static let shared = LaunchState()
    @Published private(set) var ready = false
    @Published private(set) var detail = "Checking existing browser data…"
    @Published private(set) var problem: String?
    private var task: Task<Void, Never>?
    private var waiting: [URL] = []
    var showWindow: (() -> Void)?

    func start() {
        guard !ready, task == nil else { return }
        problem = nil
        task = Task { [self] in
            do {
                if let request = LeavingTheSandbox.request() {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try LegacyDataMigration.run(library: request.library, bundle: request.bundle, completed: request.completed) { progress in
                            Task { @MainActor in
                                let name = progress.item.hasPrefix("WebKit/Website") ? "sign-ins and site data" : progress.item.hasPrefix("WebKit/") ? "content blocking data" : "spaces and bookmarks"
                                self.detail = progress.copiedFiles > 0 ? "Moving \(name). \(progress.copiedFiles) files copied." : "Moving \(name)…"
                            }
                        }
                    }.value
                    LeavingTheSandbox.finish(request, result: result)
                }
                ready = true
                // Let SwiftUI present the browser before optional startup services run.
                await Task.yield()
                Session.shared.start(afterLaunch: true)
                #if DIRECT
                Updates.shared.start()
                #endif
                if !waiting.isEmpty { Session.shared.open(waiting, fromOtherApp: true); waiting.removeAll() }
            } catch {
                problem = error.localizedDescription
            }
            task = nil
        }
    }

    /// Links from other apps, and web pages opened from Finder.
    func open(_ urls: [URL]) {
        if ready { Session.shared.open(urls, fromOtherApp: true) } else { waiting += urls; showWindow?() }
    }
}

struct LaunchProgressView: View {
    @ObservedObject private var launch = LaunchState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(launch.problem == nil ? "Preparing Your Browser" : "Browser Data Could Not Be Moved")
                .font(.title2.weight(.semibold))
            if launch.problem == nil {
                ProgressView().controlSize(.large)
                Text(launch.detail).accessibilityAddTraits(.updatesFrequently)
                Text("Your existing browser data is being kept. You can quit and continue later.").foregroundStyle(.secondary)
            } else {
                Text("Your original data is intact. Free up storage or check access to your Library folder, then retry.")
                Text(launch.problem ?? "").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Retry") { launch.start() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(minWidth: 500, minHeight: 320)
    }
}
