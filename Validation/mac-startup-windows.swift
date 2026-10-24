import Darwin

// The wrapper compiles SafienceApp.swift and WindowSeed from the production
// sources with these in-memory collaborators. No browser services or files run.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    var canUseWorkspace = true
    func requestTermination(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
}

@MainActor
final class LaunchState: ObservableObject {
    static let shared = LaunchState()
    @Published var ready = true
    private var windowAction: (() -> Void)?
    var showRequests = 0
    var showWindow: (() -> Void)? {
        get { windowAction.map { action in { self.showRequests += 1; action() } } }
        set { windowAction = newValue }
    }
    func start() {}
    func open(_ urls: [URL]) {}
}

struct BrowserCommands: Commands { var body: some Commands { CommandGroup(after: .newItem) {} } }
struct MacSettings: View { var body: some View { Text("Synthetic Settings") } }
struct WorkspaceRecoveryView: View { var body: some View { Text("Synthetic Recovery") } }
struct LaunchProgressView: View { var body: some View { Text("Synthetic Startup") } }

struct BrowserView: View {
    @Binding var seed: WindowSeed?
    var body: some View {
        Text("Synthetic Browser")
            .frame(width: 640, height: 420)
            .onAppear { StartupWindowProbe.shared.appeared() }
    }
}

@MainActor
final class StartupWindowProbe {
    static let shared = StartupWindowProbe()
    private var started = false
    private var failures = 0
    private var checks = 0
    private var retained: [NSWindow] = []

    private var browserWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.contentView != nil && $0.canBecomeMain }
    }

    func appeared() {
        guard !started else { return }
        started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            check(browserWindows.count == 1, "Fresh launch presents one browser window")
            reopen()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                check(browserWindows.count == 1, "Reopening with a visible browser creates no window")
                retained = browserWindows
                retained.forEach { $0.close() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    check(browserWindows.isEmpty, "Closing browser windows keeps the process running")
                    reopen()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                        check(browserWindows.count == 1, "Reopening after the last window closes creates exactly one browser")
                        LaunchState.shared.showWindow?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                            check(browserWindows.count == 2, "An explicit new window retains multiple browser windows")
                            reopen()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                                check(browserWindows.count == 2, "Reopening preserves two intentional browser windows")
                                retained = browserWindows
                                retained.forEach { $0.close() }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                                    reopen()
                                    reopen()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                                        check(browserWindows.count == 1, "Repeated reopen events before presentation share one browser window")
                                        print("Startup windows: \(checks - failures)/\(checks) native checks passed")
                                        fflush(stdout)
                                        exit(failures == 0 ? 0 : 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func reopen() {
        // A real reopen AppleEvent exercises the SwiftUI delegate adapter and
        // AppKit's default handling after the production delegate returns.
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(0x61657674), // aevt
                                          eventID: AEEventID(0x72617070), // rapp
                                          targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
                                          returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        do { try event.sendEvent(options: .noReply, timeout: 1) }
        catch { check(false, "Reopen AppleEvent: \(error.localizedDescription)") }
    }

    private func check(_ passed: Bool, _ label: String) {
        checks += 1
        print("\(passed ? "PASS" : "FAIL") \(label) [visible: \(browserWindows.count), explicit requests: \(LaunchState.shared.showRequests)]")
        if !passed { failures += 1 }
    }
}
