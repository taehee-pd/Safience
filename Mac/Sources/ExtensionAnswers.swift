import AppKit
import PadCore
import WebKit

/// What the shim asks of the app (Scripts/extension-shim.js), through
/// native messaging to "safience": what it tells of, and the APIs WebKit
/// lacks that the app answers. Each answer is for the extension that asked,
/// in the space it asked from. One that touches a site's data checks
/// ExtensionPolicy.mayTouchData first; none here does yet.
extension Extensions {
    struct Unanswered: LocalizedError {
        let why: String
        var errorDescription: String? { why }
    }

    /// The answer, as JSON can carry it; nil for none.
    func answer(_ api: String, _ args: [Any], context: WKWebExtensionContext, in space: UUID) async throws -> Any? {
        let id = context.uniqueIdentifier
        let first = args.first
        switch api {
        case "report":
            // An error nobody caught: [kind, its words, file, line]. Only
            // the API it names is kept, as for WebKit's own errors.
            let problem = args.count > 1 ? (args[1] as? String).flatMap { ExtensionError.problem(in: $0, missing: lacking[id] ?? []) } : nil
            #if DEBUG
            Self.note("shim report: \(problem?.api ?? "no API named")")
            #endif
            if let problem {
                update(id, in: space) { $0.problems.insert(problem) }
                // Into the records once, as WebKit's own errors go (errorsChanged).
                if let item = installed.first(where: { $0.id == id }),
                   recordOnce("\(space.uuidString)/\(id)", (args[1] as? String) ?? "") {
                    note(problem, file: args.count > 2 ? args[2] as? String : nil, of: item)
                }
            }
            return nil

        // MARK: the worker, up before a page talks to it (Search's)
        case "background.wake":
            guard context.webExtension.hasBackgroundContent else { return nil }
            // WebKit sometimes fails to start a worker again after unloading
            // it, and then never tries again: every message waits for ever.
            // Tried twice more, then the extension is taken up afresh.
            for attempt in 0..<3 {
                // WebKit never calls back after some failed starts; eight
                // seconds without an answer counts as a failure.
                let error: Error? = await withCheckedContinuation { done in
                    var finished = false
                    let finish: (Error?) -> Void = { result in
                        guard !finished else { return }
                        finished = true
                        done.resume(returning: result)
                    }
                    context.loadBackgroundContent { error in MainActor.assumeIsolated { finish(error) } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(Unanswered(why: "no answer from WebKit")) }
                }
                guard error != nil else { return nil }
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(400)) }
            }
            revive(id, in: space, because: "its worker wouldn't start")
            return nil
        case "background.revive":
            // A page found the worker gone though WebKit believes it runs.
            return revive(id, in: space, because: "its worker stopped answering")

        // MARK: its own pages, for clients.matchAll() and getContexts
        case "clients.pages":
            var pages = ownPages(of: id, in: space)
            if let url = ExtensionOffscreen.url(id, in: space) {
                pages.append(["id": "offscreen", "url": url.absoluteString, "visible": false, "focused": false])
            }
            return pages
        case "runtime.getContexts":
            // The extension's own pages that Chrome would list: its worker,
            // its pages in tabs, its offscreen document. Bitwarden asks for
            // these to know where to send its messages.
            let filter = first as? [String: Any] ?? [:]
            let types = filter["contextTypes"] as? [String]
            let urls = filter["documentUrls"] as? [String]
            var found: [[String: Any]] = []
            func add(_ type: String, _ url: URL?, contextID: String) {
                guard types == nil || types!.contains(type) else { return }
                let address = url?.absoluteString ?? ""
                guard urls == nil || urls!.contains(address) else { return }
                found.append([
                    "contextType": type, "contextId": contextID, "tabId": -1, "windowId": -1,
                    "frameId": type == "BACKGROUND" ? -1 : 0, "documentUrl": address,
                    "documentOrigin": url.map { "\($0.scheme ?? "")://\($0.host() ?? "")" } ?? "",
                    "incognito": false,
                ])
            }
            if context.webExtension.hasBackgroundContent {
                let background = context.webExtension.manifest["background"] as? [String: Any] ?? [:]
                let script = background["service_worker"] as? String ?? background["page"] as? String
                add("BACKGROUND", script.flatMap { URL(string: $0, relativeTo: context.baseURL)?.absoluteURL }, contextID: "\(id)-background")
            }
            for page in ownPages(of: id, in: space) {
                add(page["kind"] as? String ?? "TAB", (page["url"] as? String).flatMap(URL.init(string:)), contextID: page["id"] as? String ?? "")
            }
            found += ExtensionOffscreen.contexts(id, in: space, matching: filter)
            return found

        // MARK: offscreen, a page with a DOM for a worker that has none
        case "offscreen.createDocument":
            guard let path = (first as? [String: Any])?["url"] as? String
            else { throw Unanswered(why: "No page for the offscreen document") }
            try await ExtensionOffscreen.create(path, for: context, in: space)
            return nil
        case "offscreen.closeDocument":
            ExtensionOffscreen.close(id, in: space)
            return nil
        case "offscreen.hasDocument":
            return ExtensionOffscreen.hasDocument(id, in: space)

        // Supplied text only. This endpoint never reads a tab or grants access.
        case "i18n.detectLanguage":
            guard let text = first as? String else { throw Unanswered(why: "Language detection requires text.") }
            return ExtensionLanguage.detect(text).json

        // MARK: native messaging, asked for as Chrome asks
        case "permissions.native":
            // Only for an extension that asked for it as optional; one that
            // asked for it outright had it at install.
            guard asksForNativeOnlyOptionally(id) else { return reachesApps(id) }
            switch first as? String {
            case "has":
                return reachesApps(id)
            case "remove":
                setNativeConsent(id, false)
                return true
            default:
                if reachesApps(id) { return true }
                let alert = NSAlert()
                alert.messageText = "\u{201C}\(context.webExtension.displayName ?? id)\u{201D} asks to talk to apps on this Mac."
                alert.informativeText = "An app that has made itself known to Chrome for it, such as a password manager's, could exchange information with it."
                alert.addButton(withTitle: "Allow")
                alert.addButton(withTitle: "Don't Allow")
                let yes = await present(alert, in: Session.shared.frontWindow) == .alertFirstButtonReturn
                if yes { setNativeConsent(id, true) }
                return yes
            }

        // MARK: the side panel (ExtensionSidePanel.swift)
        case "sidePanel.setOptions":
            let options = first as? [String: Any] ?? [:]
            let tab = options["tabId"] == nil ? nil : self.tab(at: options["__place"], in: space)
            // A tab it named that can't be found: nothing set, rather than every tab.
            if options["tabId"] != nil, tab == nil { return nil }
            ExtensionSidePanels.shared.setOptions(id, in: space, tab: tab, path: options["path"] as? String, enabled: options["enabled"] as? Bool)
            return nil
        case "sidePanel.getOptions":
            let options = first as? [String: Any] ?? [:]
            return ExtensionSidePanels.shared.options(id, in: space, tab: self.tab(at: options["__place"], in: space))
        case "sidePanel.setPanelBehavior":
            let behavior = first as? [String: Any] ?? [:]
            if let on = behavior["openPanelOnActionClick"] as? Bool { ExtensionSidePanels.shared.setOpensOnAction(id, in: space, on) }
            return nil
        case "sidePanel.getPanelBehavior":
            return ["openPanelOnActionClick": ExtensionSidePanels.shared.opensOnAction(id, in: space)]
        case "sidePanel.open", "sidePanel.close":
            let options = first as? [String: Any] ?? [:]
            let panels = ExtensionSidePanels.shared
            let tab = self.tab(at: options["__place"], in: space)
            // A tab it named that can't be found: an error, not the tab in front.
            if options["tabId"] != nil, tab == nil { throw Unanswered(why: "No tab with id: \(options["tabId"] ?? "").") }
            let windows = Session.shared.allWindows.filter { $0.spaceID == space }
            // A tab not on screen: its panel opens when it is.
            if let tab, !windows.contains(where: { $0.tabID == tab }) {
                if api == "sidePanel.open" { panels.open(id, whenShowing: tab, in: space) } else { panels.cancel(id, tab: tab, in: space) }
                return nil
            }
            guard let window = windows.first(where: { tab != nil && $0.tabID == tab }) ?? windows.first(where: { $0.window?.isKeyWindow == true }) ?? windows.first
            else { throw Unanswered(why: "No window to open the side panel in.") }
            if api == "sidePanel.open" { ExtensionSidePanels.shared.open(id, in: window) } else if ExtensionSidePanels.shared.panel(in: window)?.surface.extensionID == id {
                ExtensionSidePanels.shared.close(in: window)
            }
            return nil

        // MARK: the popup its button opens, as it set it
        case "action.popup":
            popupPaths["\(space.uuidString)/\(id)"] = first as? String ?? ""
            return nil

        // MARK: management, itself only
        case "management.getSelf", "management.get":
            if api == "management.get", first as? String != id { throw Unanswered(why: "No extension with id \(first ?? "")") }
            return describe(context)

        default:
            throw Unanswered(why: "Safience doesn't answer \(api).")
        }
    }

    /// The tab at a place the shim found for a tab number (its index in the
    /// space's window, and its address, which must still be there).
    func tab(at place: Any?, in space: UUID) -> UUID? {
        guard let place = place as? [String: Any], let index = place["index"] as? Int,
              let tabs = Session.shared.workspace.space(space)?.tabs, tabs.indices.contains(index) else { return nil }
        let tab = tabs[index]
        if let address = place["url"] as? String, !address.isEmpty {
            let now = Session.shared.pages.live[tab.id]?.view.url ?? tab.url
            guard now?.absoluteString == address else { return nil }
        }
        return tab.id
    }

    /// The extension's own pages open in the space's tabs, as clients.matchAll lists them.
    private func ownPages(of id: String, in space: UUID) -> [[String: Any]] {
        let session = Session.shared
        var pages: [[String: Any]] = []
        for tab in session.workspace.space(space)?.tabs ?? [] {
            guard let view = session.pages.live[tab.id]?.view, let url = view.url,
                  url.scheme == Self.scheme, url.host() == id else { continue }
            let window = session.allWindows.first { $0.tabID == tab.id && $0.window?.occlusionState.contains(.visible) == true }
            pages.append(["id": tab.id.uuidString, "url": url.absoluteString,
                          "visible": window != nil, "focused": window?.window?.isKeyWindow == true])
        }
        // Its popup and side panel while they are up: 1Password's worker
        // sends its popup the app's news only when it finds it open. (Search's)
        let surfaces = ExtensionPopups.shared.shown.values.map { ($0.surface, $0.window, "POPUP") }
            + ExtensionSidePanels.shared.shown.values.map { ($0.surface, $0.window, "SIDE_PANEL") }
        for (surface, window, kind) in surfaces where surface.extensionID == id && surface.space == space {
            guard let url = surface.web.url else { continue }
            pages.append(["id": "\(kind.lowercased())-\(window.map { ObjectIdentifier($0).hashValue } ?? 0)", "url": url.absoluteString,
                          "visible": true, "focused": window?.window?.isKeyWindow == true, "kind": kind])
        }
        return pages
    }

    /// management's ExtensionInfo, of the extension itself.
    private func describe(_ context: WKWebExtensionContext) -> [String: Any] {
        let package = context.webExtension
        let item = installed.first { $0.id == context.uniqueIdentifier }
        var info: [String: Any] = [
            "id": context.uniqueIdentifier,
            "name": package.displayName ?? item?.name ?? "",
            "shortName": package.displayShortName ?? package.displayName ?? "",
            "description": package.displayDescription ?? "",
            "version": package.version ?? item?.version ?? "",
            "enabled": true, "mayDisable": true, "offlineEnabled": false,
            "type": "extension",
            "installType": item?.source == .unsigned ? "development" : "normal",
            "permissions": package.requestedPermissions.map(\.rawValue).sorted(),
            "hostPermissions": package.allRequestedMatchPatterns.map(\.string).sorted(),
            "isApp": false,
        ]
        if let options = context.optionsPageURL { info["optionsUrl"] = options.absoluteString }
        return info
    }

    /// A desktop app a host stands for, in the words a person knows it by.
    static func appName(ofHost host: String) -> String {
        let known = ["com.8bit.bitwarden": "Bitwarden", "com.1password": "1Password", "com.apple.passwordmanager": "iCloud Passwords",
                     "com.dashlane": "Dashlane", "com.lastpass": "LastPass", "com.keepassxc": "KeePassXC", "org.keepassxc": "KeePassXC"]
        return known.first { host.hasPrefix($0.key) }?.value ?? host
    }
}
