import PadCore
import SwiftUI

/// Settings (⌃⌥,). Short, because most of what this app does is meant to
/// stay out of sight; the switches here are for checking and adjusting the
/// bridges on a real iPad.
struct SettingsView: View {
    @ObservedObject var session: Session
    let done: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Show the address bar", selection: $session.preferences.address) {
                        Text("On sign-in pages and while typing").tag(AddressMode.automatic)
                        Text("Always").tag(AddressMode.always)
                    }
                    Toggle("Show the tab bar", isOn: $session.preferences.tabBar)
                } header: {
                    Text("Window")
                } footer: {
                    Text("Sign-in pages always show the address, so you can see which site is asking for your password. With the tab bar hidden, ⌃⌥K finds every tab.")
                }

                Section {
                    Stepper(value: $session.preferences.limits.lightOffScreen, in: 0...6) {
                        Text("Light tabs kept open: \(session.preferences.limits.lightOffScreen)")
                    }
                } header: {
                    Text("Memory")
                } footer: {
                    Text("One heavy tab, such as a Figma file, stays open even when you switch away; another heavy tab freezes it. Other tabs off screen beyond this number freeze too: they keep a picture and load again when you open them. iPadOS limits how much memory each page may use, and no setting can raise that.")
                }

                Section {
                    Picker("Two-finger scroll", selection: $session.preferences.wheel) {
                        Text("As each site needs").tag(WheelMode?.none)
                        Text("Bridge when WebKit sends nothing").tag(WheelMode?.some(.auto))
                        Text("Always bridge").tag(WheelMode?.some(.always))
                        Text("Never bridge").tag(WheelMode?.some(.off))
                    }
                    Picker("Tab and arrow keys", selection: $session.preferences.keys) {
                        Text("As each site needs").tag(Override.site)
                        Text("Send to the page first").tag(Override.on)
                        Text("Leave to the system").tag(Override.off)
                    }
                } header: {
                    Text("Trackpad and keyboard")
                } footer: {
                    Text("Pinch and ⌘ with two fingers zoom the page's own canvas, as on a Mac. Turn on “Send to the page first” if the system keeps Tab or the arrow keys from a page.")
                }

                Section("Search") {
                    Picker("Search engine", selection: $session.preferences.engine) {
                        ForEach(Destination.engines, id: \.id) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
                }

                Section {
                    ForEach(Adapters.all + [Adapters.standard]) { adapter in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(adapter.name)
                            Text(describe(adapter))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sites")
                }

                Section {
                    Toggle("Show diagnostics", isOn: $session.preferences.diagnostics)
                } footer: {
                    Text("A small panel over the page: which site adapter is on, what the bridges send, the user agent the page sees, and which tabs are live. ⌃⌥D shows and hides it.")
                }

                Section("Shortcuts") {
                    ForEach(Command.allCases, id: \.self) { command in
                        HStack {
                            Text(command.title)
                            Spacer()
                            Text(Shortcuts.chord(for: command)?.label ?? "")
                                .foregroundStyle(.secondary)
                                .monospaced()
                        }
                    }
                    HStack {
                        Text("A tab by its place, the last one")
                        Spacer()
                        Text("⌃⌥1 … ⌃⌥9").foregroundStyle(.secondary).monospaced()
                    }
                }

                Section("Known limitations") {
                    Text("iPadOS keeps its own shortcuts (⌘Tab, ⌘Space, the Globe key) and its three- and four-finger gestures; no app can give those to a page.")
                    Text("Passkeys need an entitlement Apple grants only to default browsers, so sign in with a password, an email link, or your company's single sign-on.")
                    Text("With VoiceOver on, ⌃⌥ is VoiceOver's own key; use the command palette instead.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }

    private func describe(_ adapter: SiteAdapter) -> String {
        let bridges = session.preferences.bridges(for: adapter)
        var parts: [String] = []
        if !adapter.domains.isEmpty { parts.append(adapter.domains.joined(separator: ", ")) }
        parts.append(bridges.pinch ? "pinch zooms" : "no pinch")
        if bridges.commandZoom { parts.append("⌘ scroll zooms") }
        parts.append("wheel bridge \(bridges.wheel.rawValue)")
        if !bridges.keys.isEmpty { parts.append("keys: " + bridges.keys.map(\.rawValue).sorted().joined(separator: ", ")) }
        if !adapter.heavyPaths.isEmpty { parts.append("files are heavy") }
        return parts.joined(separator: " · ")
    }
}
