import AppKit
import PadCore
import SwiftUI

struct ExtensionSettings: View {
    @ObservedObject private var extensions = Extensions.shared
    @ObservedObject private var session = Session.shared
    @AppStorage(Extensions.checksKey) private var checksDaily = true
    @State private var checking = false
    @State private var host: NSWindow?
    @State private var result: ExtensionUpdateReport?

    var body: some View {
        Form {
            if let problem = extensions.listSaveProblem {
                Section {
                    Text(problem).foregroundStyle(.orange)
                    Button("Retry Saving Extensions") { extensions.retryListSave() }
                }
            }
            if extensions.installed.isEmpty {
                Section { Text("No extensions installed. Add one from the Chrome Web Store or a file.").foregroundStyle(.secondary) }
            }
            ForEach(extensions.installed) { item in
                Section {
                    Text(Self.source(of: item)).foregroundStyle(.secondary)
                    if extensions.isIncompatible(item.id) {
                        Label("Incompatible with this Mac", systemImage: "exclamationmark.triangle.fill")
                        Text(extensions.incompatibility(item.id)).foregroundStyle(.secondary)
                    }
                    Picker("Site access", selection: Binding(get: { item.siteAccess }, set: { extensions.setSiteAccess(item.id, $0) })) {
                        Text("On Requested Sites").tag(Extensions.Installed.SiteAccess.allSites)
                        Text("Only When I Click It").tag(Extensions.Installed.SiteAccess.onClick)
                    }
                    DisclosureGroup("Capabilities and sites requested") {
                        ForEach(extensions.accessDescriptions(item.id), id: \.self) { Text($0) }
                        Text("Google's sign-in pages and cookie access remain blocked.").foregroundStyle(.secondary)
                    }
                    ForEach(session.workspace.spaces) { space in
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: Binding(get: { item.spaces.contains(space.id) },
                                                 set: { extensions.turn(item.id, on: $0, in: space.id) })) {
                                Label(space.name, systemImage: space.symbol)
                            }
                            .disabled(extensions.isIncompatible(item.id) && !item.spaces.contains(space.id))
                            if item.spaces.contains(space.id), let warning = extensions.warning(item.id, in: space.id) {
                                Text(([warning.title] + warning.lines).joined(separator: " "))
                                    .foregroundStyle(.orange).font(.callout)
                            }
                            if item.spaces.contains(space.id) {
                                Button("Remove Data from \(space.name)…", role: .destructive) {
                                    extensions.confirmRemoval(of: item.id, from: space.id, in: nil, host: host)
                                }
                            }
                        }
                    }
                    HStack {
                        Button("Move Up") { extensions.move(item.id, by: -1) }
                            .disabled(extensions.installed.first?.id == item.id)
                        Button("Move Down") { extensions.move(item.id, by: 1) }
                            .disabled(extensions.installed.last?.id == item.id)
                        Spacer()
                        if item.source == .unpacked { Button("Reload") { extensions.reload(item.id, host: host) } }
                        Button("Report a Problem…") { ExtensionReport.show(item.id, in: nil, host: host) }
                    }
                    if extensions.saidLooksWrong(item.id) {
                        Button("Show Warnings Again") { extensions.setLooksWrong(item.id, false) }
                    } else if extensions.isWarned(item.id) {
                        Button(extensions.isIncompatible(item.id) ? "Try This Version Again and Hide Its Warnings" : "Hide Warnings for This Version") {
                            extensions.setLooksWrong(item.id, true)
                        }
                    }
                    Button("Remove from Safience…", role: .destructive) {
                        extensions.confirmRemoval(of: item.id, in: nil, host: host)
                    }
                } header: {
                    Text("\(item.name) \(item.version)")
                } footer: {
                    Text("Each space keeps separate extension sign-ins and data. Turning it off keeps that data. Removing data cannot be undone. New spaces are not added automatically.")
                }
            }
            Section("Updates") {
                Toggle("Check for updates daily", isOn: $checksDaily)
                Button(checking ? "Checking…" : "Check Again") {
                    checking = true
                    Task {
                        result = await extensions.checkForUpdates(now: true, host: host)
                        checking = false
                    }
                }
                .disabled(checking || !extensions.installed.contains { $0.source == .store })
                if let report = result ?? extensions.updateReport {
                    Text(report.summary).textSelection(.enabled)
                    ForEach(Array(report.entries.enumerated()), id: \.offset) { _, entry in
                        if let detail = entry.detail {
                            Text("\(entry.name): \(detail)").foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                } else if let last = Extensions.lastChecked {
                    Text("Last checked \(last.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                }
                Text("The check sends the IDs and installed versions of your Chrome Web Store extensions to Google.").foregroundStyle(.secondary)
            }
            Section("Add") {
                Button("Chrome Web Store") { Session.shared.open([URL(string: "https://chromewebstore.google.com/category/extensions")!]) }
                Button("Install from File…") { extensions.addFromFile(in: nil, host: host) }
                Button("Load Unpacked…") { extensions.loadUnpacked(in: nil, host: host) }
            }
        }
        .background(ExtensionSettingsWindowReader { host = $0 })
    }

    static func source(of item: Extensions.Installed) -> String {
        switch item.source {
        case .store: return "from the Chrome Web Store"
        case .file: return "from a file, signed by its developer"
        case .unsigned: return "from a file, unsigned"
        case .unpacked: return "loaded from a folder"
        }
    }
}

/// Captures the Settings window, including when no browser window exists.
private struct ExtensionSettingsWindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Reader { Reader(found: found) }
    func updateNSView(_ view: Reader, context: Context) { view.found = found }
    final class Reader: NSView {
        var found: (NSWindow?) -> Void
        init(found: @escaping (NSWindow?) -> Void) { self.found = found; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let owner = window
            DispatchQueue.main.async { [weak self] in self?.found(owner) }
        }
    }
}
