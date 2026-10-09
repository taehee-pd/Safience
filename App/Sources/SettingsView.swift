import PadCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings (⌃⌥,). Short, because most of what this app does is meant to
/// stay out of sight; the switches here are for checking and adjusting the
/// bridges on a real iPad.
struct SettingsView: View {
    @ObservedObject var session: Session
    /// The space of the window Settings opened from, which imports go into.
    let spaceID: UUID
    let done: () -> Void
    @State private var importing = false
    @State private var imported: (title: String, message: String)?
    /// An iPhone: one bar at the bottom whatever the layout, no trackpad,
    /// rarely a keyboard. (An iPad in a narrow window keeps every setting:
    /// it widens again.)
    private let phone = UIDevice.current.userInterfaceIdiom == .phone

    var body: some View {
        NavigationStack {
            Form {
                DefaultBrowserSection()

                CloudSection(session: session)

                AppIconSection()

                if phone {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cursor speed")
                            HStack(spacing: 10) {
                                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                                Slider(value: $session.preferences.cursorSpeed, in: DesktopView.cursorSpeeds)
                                    .accessibilityLabel("Cursor speed")
                                Image(systemName: "hare.fill").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Desktop View")
                    } footer: {
                        Text("How far the cursor goes as your finger moves, in Desktop View (the page's menu). It goes further the faster you move, whatever the speed.")
                    }
                    Section {
                        // Its choices as rows: a menu beside a label this long has no room on a phone.
                        Picker("The address bar shows", selection: $session.preferences.address) {
                            Text("The page's address").tag(AddressMode.always)
                            Text("The page's title").tag(AddressMode.automatic)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("The address bar shows")
                    } footer: {
                        Text("Sign-in pages always show the address, so you can see which site is asking for your password.")
                    }
                } else {
                Section {
                    Picker("Tabs", selection: $session.preferences.layout) {
                        Text("Compact").tag(TabLayout.compact)
                        Text("Separate").tag(TabLayout.separate)
                    }
                    if session.preferences.layout == .separate {
                        Picker("Show the address bar", selection: $session.preferences.address) {
                            Text("On sign-in pages and while typing").tag(AddressMode.automatic)
                            Text("Always").tag(AddressMode.always)
                        }
                    } else {
                        Picker("The tab you are on shows", selection: $session.preferences.address) {
                            Text("Its address").tag(AddressMode.always)
                            Text("Its title").tag(AddressMode.automatic)
                        }
                    }
                    Toggle("Show the tab bar", isOn: $session.preferences.tabBar)
                } header: {
                    Text("Window")
                } footer: {
                    Text("Compact puts the tabs and the address in one row, as Safari's compact layout does: a click on the tab you are on types a new address. Separate puts the address bar under the tabs. Sign-in pages always show the address, so you can see which site is asking for your password. With the tab bar hidden, ⌃⌥K finds every tab.")
                }
                }

                Section {
                    NavigationLink {
                        SpaceList(session: session)
                    } label: {
                        HStack {
                            Text("Spaces")
                            Spacer()
                            Text("\(session.workspace.spaces.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Button("Import Bookmarks into \(session.workspace.space(spaceID)?.name ?? "This Space")…") {
                        importing = true
                    }
                } footer: {
                    Text("Each space has its own name, colour and icon, its own sign-ins and its own bookmarks, which a new tab shows. Import from Chrome (Bookmark Manager › Export Bookmarks), from Safari on a Mac (File › Export › Bookmarks), or the ZIP Safari on this \(phone ? "iPhone" : "iPad") saves from Settings › Apps › Safari › Export.")
                }

                Section {
                    Stepper(value: $session.preferences.limits.lightOffScreen, in: 0...6) {
                        Text("Light tabs kept open: \(session.preferences.limits.lightOffScreen)")
                    }
                } header: {
                    Text("Memory")
                } footer: {
                    Text("One heavy tab, such as a Figma file, stays open even when you switch away; another heavy tab freezes it. Other tabs off screen beyond this number freeze too: they keep a picture and load again when you open them. \(phone ? "iOS" : "iPadOS") limits how much memory each page may use, and no setting can raise that.")
                }

                if !phone {
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
                    Toggle("Show pages' own cursors", isOn: $session.preferences.pageCursors)
                } header: {
                    Text("Trackpad and keyboard")
                } footer: {
                    Text("Pinch and ⌘ with two fingers zoom the page's own canvas, as on a Mac. Tab reaches the page first on every site, since the system keeps it otherwise; turn on “Send to the page first” if the system keeps the arrow keys from a page too. A page's own cursor, such as Figma's tools, takes the pointer's place; turn it off to keep the iPad's pointer.")
                }
                }

                Section("Search") {
                    Picker("Search engine", selection: $session.preferences.engine) {
                        ForEach(Destination.engines, id: \.id) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
                }

                BlockingSection(session: session)

                Section {
                    Toggle("Show diagnostics", isOn: $session.preferences.diagnostics)
                } footer: {
                    Text("A small panel over the page: which site adapter is on, what the bridges send, the user agent the page sees, and which tabs are live. ⌃⌥D shows and hides it.")
                }

                if !phone {
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
                    Text("With VoiceOver on, ⌃⌥ is VoiceOver's own key; use the command palette instead.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.html, .zip]) { result in
                guard case .success(let file) = result else { return }
                let scoped = file.startAccessingSecurityScopedResource()
                defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                imported = session.importBookmarks(from: file, into: spaceID)
            }
            .alert(imported?.title ?? "", isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } })) {
                Button("OK") { imported = nil }
            } message: {
                Text(imported?.message ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }

}

/// Ads and trackers (ContentBlocker): on or off, the sites it is off for,
/// and whose lists they are, as their licence asks.
private struct BlockingSection: View {
    @ObservedObject var session: Session
    @ObservedObject private var blocker = ContentBlocker.shared

    var body: some View {
        Section {
            Toggle("Block ads and trackers", isOn: $session.preferences.blocksContent)
            if session.preferences.blocksContent {
                if let shown = blocker.shown {
                    ForEach(shown.lists) { list in
                        LabeledContent(list.name) {
                            Text(list.made.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown")
                                .monospacedDigit()
                        }
                    }
                    LabeledContent("Rules") {
                        Text(shown.rules.formatted(.number)).monospacedDigit()
                    }
                } else {
                    LabeledContent("Lists") { Text("Getting ready…") }
                }
            }
            if session.preferences.blocksContent && !session.preferences.unblockedSites.isEmpty {
                let count = session.preferences.unblockedSites.count
                Button("Block on All Sites Again (\(count) allowed)") {
                    session.preferences.unblockedSites = []
                }
            }
        } header: {
            Text("Ads and trackers")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "Blocked by WebKit itself before they load, with \(ContentBlocking.credit). "
        text += "A site's menu can allow them on that site. Sign-in pages are never touched. Each list's date is the day it was made; the lists update themselves."
        if session.preferences.blocksContent, let dropped = blocker.shown?.dropped, dropped > 0 {
            text += " \(dropped) of WebKit's rule lists couldn't be made, so some ads still show."
        }
        return text
    }
}

/// The Home Screen icon: Safience, the app's own, or one of the alternates the
/// asset catalog compiles in (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in
/// project.yml), each the globe and pointer drawn in a style of its own. The system keeps the choice, so nothing here stores it; each
/// preview is that icon rendered in light and dark, so it matches the screen.
private struct AppIconSection: View {
    private struct Choice: Identifiable {
        /// The alternate's name, as the project lists it; nil is the app's own icon.
        let name: String?
        let title: String
        var id: String { title }
    }

    private static let choices = [Choice(name: nil, title: "Safience")]
        + ["Diazo", "Engineer", "Signal", "Lilac", "Oxide", "Citrus", "Midnight"].map { Choice(name: $0, title: $0) }

    @State private var current = UIApplication.shared.alternateIconName
    @State private var failure: String?

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 16) {
                    ForEach(Self.choices) { choice in
                        let chosen = choice.name == current
                        Button { choose(choice) } label: {
                            VStack(spacing: 6) {
                                Image("IconPreview\(choice.title)")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .padding(4)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2.5)
                                    }
                                Text(choice.title)
                                    .font(.caption)
                                    .foregroundStyle(chosen ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("App icon")
            } footer: {
                Text(failure ?? "Safience is the app's own. The others draw the same globe and pointer their own way: a terminal's pixels, an engraving, an LED board, an orbit in glass, a linocut, a poster and a star chart. The system says once that the icon changed.")
            }
        }
    }

    private func choose(_ choice: Choice) {
        guard choice.name != current else { return }
        // The ring moves at the tap; the system's own notice comes after.
        let previous = current
        current = choice.name
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.name)
                failure = nil
            } catch {
                // The system refused (it does while the app is not in front, or when it is busy): say so, put the ring back.
                current = previous
                failure = "The icon couldn't change: \(error.localizedDescription)"
            }
        }
    }
}
