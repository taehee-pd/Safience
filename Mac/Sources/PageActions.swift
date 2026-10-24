import AppKit
import PadCore
import SwiftUI

/// The page's own commands, behind the share symbol beside the address, as
/// the iPhone's page menu (…) has them: Find, Share and Handoff side by
/// side, each its symbol over its name, as the iPhone's menu sets its row
/// of three; then Copy Link, the bookmark, ads on this site and the pin;
/// then Commands and Settings. What only a phone has (Desktop View) is left
/// out. Sharing is the Mac's own menu of ways, and like Copy Link it sends
/// the address without the tags that follow whoever opens it (Tracking.clean).
struct PageActions: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var session = Session.shared
    @State private var shareAnchor = Anchor()

    var body: some View {
        let url = model.url.flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil }
        VStack(spacing: 0) {
            if let url {
                HStack(spacing: 6) {
                    ActionTile("Find", symbol: "text.magnifyingglass") {
                        close()
                        model.startFinding()
                    }
                    ActionTile("Share", symbol: "square.and.arrow.up") {
                        guard let view = shareAnchor.view else { return }
                        model.sharing.show([Tracking.clean(url) as NSURL], from: view) { service in
                            if service != nil { close() }
                        }
                    }
                    .background(AnchorView(anchor: shareAnchor))
                    if model.canHandoff {
                        ActionTile("Send to App", symbol: Command.handoff.symbol) {
                            close()
                            model.startHandoff()
                        }
                    }
                }
                .padding(Metrics.gap)
                Divider()
                VStack(spacing: 0) {
                    ActionRow("Copy Link", symbol: "doc.on.doc", keys: "⇧⌘C") {
                        model.copyLink()
                        close()
                    }
                    ActionRow(model.isBookmarked ? "Remove Bookmark" : "Bookmark This Page",
                              symbol: model.isBookmarked ? "star.slash" : "star", keys: "⌘D") {
                        model.toggleBookmark()
                        close()
                    }
                    if session.preferences.blocksContent, url.host != nil {
                        ActionRow(model.blocksContentHere ? "Allow Ads on This Site" : "Block Ads on This Site",
                                  symbol: model.blocksContentHere ? "shield.slash" : "shield") {
                            model.toggleBlocking()
                            close()
                        }
                    }
                    pinRow
                }
                .padding(6)
                Divider()
            } else if model.tab?.isPinned == true {
                VStack(spacing: 0) { pinRow }
                    .padding(6)
                Divider()
            }
            VStack(spacing: 0) {
                ActionRow(Command.everything.title, symbol: "command") {
                    close()
                    model.commandBar = .newTab
                }
                ActionRow("Settings…", symbol: "gearshape", keys: "⌘,") {
                    close()
                    session.openSettings?()
                }
            }
            .padding(6)
        }
        .frame(width: 272)
    }

    @ViewBuilder private var pinRow: some View {
        if let tab = model.tab {
            if tab.isPinned {
                ActionRow("Unpin Tab", symbol: "pin.slash", keys: "⇧⌘D") {
                    model.togglePin()
                    close()
                }
            } else if tab.url != nil {
                ActionRow("Pin Tab", symbol: "pin", keys: "⇧⌘D") {
                    model.togglePin()
                    close()
                }
            }
        }
    }

    private func close() {
        model.pageActionsShown = false
    }
}

/// One of the three side by side: its symbol over its name, on a quiet
/// ground that darkens under the pointer and gives a little when pressed.
private struct ActionTile: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(ActionTileStyle())
        .accessibilityLabel(title)
    }
}

private struct ActionTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionTileBody(configuration: configuration)
    }
}

private struct ActionTileBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .foregroundStyle(Color.primary)
            .background(shape.fill(Palette.wash))
            .overlay(Highlight(hovering: hovering, pressed: configuration.isPressed, shape: shape))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// A row of the list under them: its symbol, its name, and its keys.
private struct ActionRow: View {
    let title: String
    let symbol: String
    var keys: String?
    let action: () -> Void

    init(_ title: String, symbol: String, keys: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.keys = keys
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let keys {
                    Text(keys)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        .buttonStyle(RowButtonStyle())
    }
}

// MARK: The Mac's share menu

/// The Mac's menu of ways to share (NSSharingServicePicker), shown from a
/// view under SwiftUI's. `done` hears the way picked, or nil when none was.
@MainActor
final class Sharing: NSObject, NSSharingServicePickerDelegate {
    private var picker: NSSharingServicePicker?
    private var done: ((NSSharingService?) -> Void)?

    func show(_ items: [Any], from view: NSView, done: @escaping (NSSharingService?) -> Void) {
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        self.picker = picker
        self.done = done
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated {
            done?(service)
            done = nil
            self.picker = nil
        }
    }
}

/// Where a SwiftUI view is, as AppKit has it: a menu of AppKit's is shown
/// from it (Sharing).
final class Anchor {
    weak var view: NSView?
}

struct AnchorView: NSViewRepresentable {
    let anchor: Anchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

// MARK: Handoff

/// Handoff on a Mac: the iPad's sheet (HandoffGuide) as a pane of glass at
/// the page's corner while the page is read and, where Apple Intelligence's
/// model is there, while the model reads it (HandoffJob). It holds nothing
/// up: the sidebar, the other tabs and the page itself go on working
/// meanwhile, and it says which page it is about, should another be on
/// screen by the time it is ready. Its Share button shows the Mac's share
/// menu from itself; an app picked is given the file and the words beside
/// it, and the pane goes. The menu closed with nothing picked leaves it as
/// it was; its × puts it away, and the handoff with it.
///
/// Its corners are an extension popup's (PopupMetrics), not the iPad
/// sheet's: the pane's 20, the Share button's 10, standing 10 in from it,
/// so the Mac's panes of glass read as one family.
struct HandoffPanel: View {
    @ObservedObject var model: WindowModel
    let job: HandoffJob
    @State private var shareAnchor = Anchor()
    private let corners = HandoffGuide.Corners(outer: PopupMetrics.corner, edge: PopupMetrics.inset)

    var body: some View {
        let colour = model.space?.color ?? .blue
        let shape = RoundedRectangle(cornerRadius: corners.outer, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SiteIconView(url: job.page, size: 16)
                Text(job.pageTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                    model.endHandoff(taken: false)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PlainIconStyle())
                .help("Put Away")
                .accessibilityLabel("Close Send to App")
            }
            .padding(.leading, corners.edge + 8)
            .padding(.trailing, 10)
            .padding(.top, 10)
            HandoffGuide(job: job, colour: colour, foot: corners.edge, corners: corners) {
                guard let view = shareAnchor.view else { return }
                model.shareHandoff(from: view)
            }
            // The guide's own room above its title is the row's now.
            .padding(.top, -22)
        }
        // The share menu comes from the foot of the pane, where its button is.
        .overlay(alignment: .bottom) {
            AnchorView(anchor: shareAnchor)
                .frame(width: 1, height: 1)
                .padding(.bottom, corners.edge + 40)
        }
        .frame(width: 400)
        .clipShape(shape)
        .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.75)), in: shape)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }
}
