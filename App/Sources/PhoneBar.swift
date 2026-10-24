import Combine
import PadCore
import SwiftUI
import UIKit

/// The bars on a phone-width window (an iPhone, the iPhone Duo folded, a
/// narrow iPad window), at the bottom where a thumb reaches, as Safari and
/// Comet have them: the address across the width with the page's menu beside
/// it, and under it one row of tools packed around the space, drawn plain so
/// the address and the space stand out. While an address is typed only the
/// address shows, over the keyboard, with Cancel. A swipe up on the bar
/// shows the space's tabs (Browser.swipedBar); a swipe sideways goes to the
/// tab beside, the address going with the finger and the next tab's coming
/// in next to it (Browser.slidBar).
///
/// Beside the iPhone Duo's strip (WindowModel.strip) the bar is one row:
/// the space, then the address. The tools and the page's menu are the
/// strip's there (StripItems), as Docs/iPhoneDuoDesign.md §3 has them.
struct PhoneBar: View {
    @ObservedObject var session: Session
    let window: WindowModel
    let act: (BarAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The address over a row of tools, each 44 points, with room between
    /// so the two rows read apart.
    static var height: CGFloat { 6 + BarScale.thumb.control + rowGap + 44 }
    private static let rowGap: CGFloat = 10
    /// The address alone, over the keyboard.
    static var typingHeight: CGFloat { 6 + BarScale.thumb.control + 6 }
    /// The one row beside the iPhone Duo's strip, typing or not.
    static var stripHeight: CGFloat { 6 + BarScale.thumb.control + 6 }

    /// The bar's height when nothing is typed, which is how much of the
    /// page it covers: one row beside a strip, two anywhere else.
    static func resting(strip: Bool) -> CGFloat {
        strip ? stripHeight : height
    }

    var body: some View {
        let typing = window.editingAddress
        // The tools go when the bar has made room for the keyboard, which
        // the first time is when the keyboard comes and not at the tap.
        let riding = window.barRidesKeyboard
        let strip = window.strip != nil
        // While the tab on screen is pinned: before the address, or after it
        // beside a strip, where the space's button is before it.
        let pinned = typing ? nil : window.tabID.flatMap { session.workspace.tab($0) }.flatMap { $0.isPinned ? $0 : nil }
        VStack(spacing: Self.rowGap) {
            SlidingRow(slide: window.slide, typing: typing, space: strip ? session.workspace.space(window.spaceID) : nil) {
                HStack(spacing: 8) {
                    if strip && !typing {
                        // As wide as its name, up to a point.
                        SpaceButton(session: session, window: window, act: act, besideAddress: true)
                            .fixedSize()
                            .transition(before)
                    }
                    if let pinned, !strip {
                        PinnedButton(tab: pinned, window: window, act: act)
                            .transition(appearing)
                    }
                    AddressCapsule(window: window, editable: window.phone, act: act)
                    if let pinned, strip {
                        PinnedButton(tab: pinned, window: window, act: act)
                            .transition(appearing)
                    }
                    if typing {
                        Button("Cancel") { act(.cancelAddress) }
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 4)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                            .transition(beside)
                    } else if !strip {
                        DownloadActivityButton { act(.downloads) }
                        PageMenu(session: session, window: window, act: act)
                            .transition(beside)
                    }
                }
                .padding(.horizontal, 12)
            }
            if !riding && !strip {
                PhoneTools(session: session, window: window, act: act)
                    .frame(height: 44)
                    .transition(.opacity)
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.barScale, .thumb)
        // Loading shows along the top edge here, next to the page.
        .overlay(alignment: .top) { LoadingLine(window: window) }
        .animation(.bar, value: typing)
        .animation(.bar, value: riding)
        .animation(.spring(duration: 0.3, bounce: 0), value: pinned?.id)
        .ignoresSafeArea(.keyboard)
    }

    /// Cancel and the page's menu trade places beside the address: sliding
    /// in from the edge, or only fading under Reduce Motion.
    private var beside: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    /// The space button, beside a strip, makes way for the typing from the other side.
    private var before: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

    /// The pinned button comes into being where it stands, from a little
    /// smaller and soft, as the address makes room; it never grows from nothing.
    private var appearing: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
}

/// The address row as a sideways drag moves it, with the next tab's row
/// coming in beside it. It watches the slide alone, so a drag moves this row
/// and draws nothing else of the bar again.
private struct SlidingRow<Row: View>: View {
    @ObservedObject var slide: BarSlide
    let typing: Bool
    /// Beside a strip, the space the row starts with; nil where the row ends with the page's menu.
    let space: Space?
    @ViewBuilder let row: Row

    var body: some View {
        let moving = row
            .offset(x: slide.offset)
            .overlay {
                if let coming = slide.coming, !typing {
                    GeometryReader { row in
                        ComingAddress(coming: coming, space: space)
                            .padding(.horizontal, 12)
                            // A row's width and the pages' gap along: where it will be once it is in.
                            .offset(x: slide.offset + coming.side * (row.size.width + 16))
                    }
                    .accessibilityHidden(true)
                }
            }
        if space != nil {
            // Beside a strip the rows come and go at its edge, as the pages
            // do, rather than under it; the glass's edges still show above and below.
            moving.mask { Rectangle().padding(.vertical, -12) }
        } else {
            moving
        }
    }
}

/// The address row of the tab a sideways drag is going to, drawn as the bar
/// will draw it once that tab is on screen: its capsule with the site's icon
/// and its name or address, and the menu's button beside it, or beside a
/// strip the space's button before it. It only shows; the real row takes
/// its place when the drag has gone through.
private struct ComingAddress: View {
    let coming: SlideNeighbour
    let space: Space?

    var body: some View {
        HStack(spacing: 8) {
            if let space {
                SpaceFace(space: space, besideAddress: true)
                    .fixedSize()
            } else if coming.tab.isPinned {
                PinnedDisc(tab: coming.tab)
            }
            NeighbourAddress(tab: coming.tab, titled: coming.titled)
            if space == nil {
                MoreDisc()
            } else if coming.tab.isPinned {
                PinnedDisc(tab: coming.tab)
            }
        }
    }
}

/// The phone bar's row of tools around the space in the middle: back and
/// forward on one side, a new tab and the tabs on the other, the gaps
/// between them shared out evenly across the width. Two tools a side, so
/// the space sits at the centre whatever its name.
private struct PhoneTools: View {
    @ObservedObject var session: Session
    let window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ToolIcon(symbol: "chevron.left", label: "Back", enabled: window.canGoBack) { act(.back) }
            Spacer(minLength: 4)
            ToolIcon(symbol: "chevron.right", label: "Forward", enabled: window.canGoForward) { act(.forward) }
            Spacer(minLength: 4)
            // As wide as its name, up to a point.
            SpaceButton(session: session, window: window, act: act)
                .fixedSize()
            Spacer(minLength: 4)
            ToolIcon(symbol: "plus", label: "New Tab") {
                // Felt as the tab is made: the page under the bar is another
                // one at once, and the keyboard only comes a moment after.
                act(.command(.newTab))
            }
            Spacer(minLength: 4)
            TabsButton(tabs: session.workspace.space(window.spaceID)?.tabs ?? [], current: window.tabID, act: act)
        }
        .padding(.horizontal, 12)
    }
}

/// A tool on the phone bar: a symbol alone, 44 points of it answering a touch.
private struct ToolIcon: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                // Dimmed by opacity, not a solid grey: the page shows through the
                // bar, and a light grey vanishes over a light one.
                .foregroundStyle(enabled ? Palette.ink : Palette.ink.opacity(0.3))
                // A chevron's point sits off its box; nudged toward the way it points.
                .offset(x: symbol == "chevron.left" ? -0.5 : symbol == "chevron.right" ? 0.5 : 0)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The tabs, drawn as the iPhone Duo strip's are (StripItems): the system's
/// two squares with how many tabs the space has open on a badge in ink at
/// their corner; its pinned tabs aren't counted, since they don't close and
/// sit apart in the dock. A tap shows them; a long press has Safari's menu:
/// a new tab, closing this one, closing them all.
private struct TabsButton: View {
    let tabs: [TabRecord]
    let current: UUID?
    let act: (BarAction) -> Void

    var body: some View {
        let ordinary = tabs.filter { !$0.isPinned }
        Menu {
            Button("New Tab", systemImage: "plus.square.on.square") { act(.command(.newTab)) }
            if !Session.shared.workspace.closed.isEmpty {
                Button("Reopen Closed Tab", systemImage: "arrow.uturn.backward") { act(.command(.reopenTab)) }
            }
            if let current, ordinary.contains(where: { $0.id == current }) {
                Button("Close This Tab", systemImage: "xmark", role: .destructive) { act(.close(current)) }
            }
            if ordinary.count > 1 {
                Button("Close All \(ordinary.count) Tabs", systemImage: "xmark.square.fill", role: .destructive) {
                    act(.closeTabs(ordinary.map(\.id)))
                }
            }
        } label: {
            Image(systemName: "square.on.square")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.ink)
                .overlay(alignment: .topTrailing) {
                    if !ordinary.isEmpty { TabCountBadge(count: ordinary.count) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        } primaryAction: {
            act(.showTabs)
        }
        .accessibilityLabel("Tabs, \(ordinary.count)")
        .accessibilityHint("Or swipe up on the bar")
    }
}

/// A count on a badge as the system draws a bar button item's: white on ink,
/// round for one digit and longer for more, its centre a point past the
/// symbol's corner and six above it.
private struct TabCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.ground)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Palette.ink))
            .fixedSize()
            // From the image's corner, which stands a little out from the
            // squares it draws, to over the squares' own corner, as the strip's.
            .offset(x: 7, y: -12)
    }
}

/// The page's own commands, which the iPad has on its tabs' menus and on ⌃⌥:
/// a round glass button beside the address, as high as it.
private struct PageMenu: View {
    @ObservedObject var session: Session
    let window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        // In the order the strip's overflow has them too (MenuEntry.overflow).
        Menu {
            PageItems(window: window, act: act)
            MenuButtons(entries: MenuEntry.tab(session, window, act: act))
            Section { AppItems(act: act) }
        } label: {
            MoreDisc()
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }
}

/// The page menu's button as it is drawn: a round glass disc beside the
/// address, as high as it, with an ellipsis. Drawn alone too, in the row a
/// sideways swipe brings in (ComingAddress).
private struct MoreDisc: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44)
            .liquidGlass(in: Circle(), otherwise: Palette.wash)
    }
}

/// The iPhone Duo's strip, the system's vertical bar beside the window, closed
/// or open (Docs/iPhoneDuoDesign.md §3): Back and Forward at its top, the
/// system's overflow (…) under them with the page's menu, New Tab and the
/// tabs at its foot, the count of tabs as the item's badge. The system puts
/// them there from the navigation item and the toolbar's items, which show
/// only while the window has a strip (Browser.showStrip). Beside a
/// phone-width window the phone bar is one row, the space and the address;
/// beside a wide one the iPad's bars stay along the top.
@MainActor
final class StripItems {
    private let session: Session
    private let window: WindowModel
    private let back: UIBarButtonItem
    private let forward: UIBarButtonItem
    private let tabs: UIBarButtonItem
    private var subscriptions: Set<AnyCancellable> = []
    /// Where the items stand, and the strip's foot: New Tab, and the tabs'
    /// item while it shows (showsTabs).
    private weak var controller: UIViewController?
    private let foot: (newTab: UIBarButtonItem, tabs: UIBarButtonItem)
    private var tabsShown = true

    init(in controller: UIViewController, session: Session, window: WindowModel, act: @escaping (BarAction) -> Void) {
        func item(_ title: String, _ symbol: String, menu: UIMenu? = nil, _ action: @escaping () -> Void) -> UIBarButtonItem {
            let item = UIBarButtonItem(title: title, image: UIImage(systemName: symbol),
                                       primaryAction: UIAction { _ in action() }, menu: menu)
            if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
            return item
        }
        let back = item("Back", "chevron.left") { act(.back) }
        let forward = item("Forward", "chevron.right") { act(.forward) }
        let newTab = item("New Tab", "plus") {
            act(.command(.newTab))
        }
        // A tap shows them; a hold has the phone bar's tabs menu (TabsButton).
        let tabsMenu = UIMenu(children: [UIDeferredMenuElement.uncached { done in
            let ordinary = (session.workspace.space(window.spaceID)?.tabs ?? []).filter { !$0.isPinned }
            var items = [UIAction(title: "New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                act(.command(.newTab))
            }]
            if !session.workspace.closed.isEmpty {
                items.append(UIAction(title: "Reopen Closed Tab", image: UIImage(systemName: "arrow.uturn.backward")) { _ in act(.command(.reopenTab)) })
            }
            if let current = window.tabID, ordinary.contains(where: { $0.id == current }) {
                items.append(UIAction(title: "Close This Tab", image: UIImage(systemName: "xmark"), attributes: .destructive) { _ in
                    act(.close(current))
                })
            }
            if ordinary.count > 1 {
                items.append(UIAction(title: "Close All \(ordinary.count) Tabs", image: UIImage(systemName: "xmark.square.fill"),
                                      attributes: .destructive) { _ in act(.closeTabs(ordinary.map(\.id))) })
            }
            done(items)
        }])
        let tabs = item("Tabs", "square.on.square", menu: tabsMenu) { act(.showTabs) }
        // The last to go into the overflow when the strip is short: the landscape strip, the keyboard's.
        if #available(iOS 27.0, *) {
            back.visibilityPriority = .high
            tabs.visibilityPriority = .high
        }
        controller.navigationItem.leadingItemGroups = [UIBarButtonItemGroup(barButtonItems: [back, forward], representativeItem: nil)]
        controller.navigationItem.additionalOverflowItems = UIDeferredMenuElement.uncached { done in
            done(MenuEntry.overflow(session, window, act: act))
        }
        controller.toolbarItems = [newTab, tabs]
        self.controller = controller
        foot = (newTab, tabs)

        self.session = session
        self.window = window
        self.back = back
        self.forward = forward
        self.tabs = tabs
        showGoing()
        showCount(in: session.workspace)
        // Through the owner, never the window itself: the window keeps what
        // watches it until its next change, and must not be kept by it.
        watch(self, read: { _ = $0.window.canGoBack; _ = $0.window.canGoForward }, changed: { $0.showGoing() })
        watch(self, read: { _ = $0.window.spaceID }, changed: { $0.showCount(in: $0.session.workspace) })
        // The workspace as it is about to be, as @Published tells it.
        session.$workspace.sink { [weak self] in self?.showCount(in: $0) }.store(in: &subscriptions)
    }

    private func showGoing() {
        back.isEnabled = window.canGoBack
        forward.isEnabled = window.canGoForward
    }

    /// How many tabs the space has open: its pinned tabs aren't counted, as
    /// on the phone bar's square.
    private func showCount(in workspace: Workspace) {
        let count = (workspace.space(window.spaceID)?.tabs ?? []).filter { !$0.isPinned }.count
        if #available(iOS 26.0, *) {
            // A count, not an alert: in the ink the phone bar's square is drawn in, rather than red.
            var badge = UIBarButtonItem.Badge.count(count)
            badge.backgroundColor = Palette.UI.ink
            badge.foregroundColor = Palette.UI.ground
            tabs.badge = count > 0 ? badge : nil
        }
        tabs.accessibilityLabel = "Tabs, \(count)"
    }

    /// The tabs' item, only where the tabs aren't on screen already: none
    /// beside a sidebar of tabs (Settings › Tabs › Vertical).
    func showsTabs(_ shown: Bool) {
        guard shown != tabsShown else { return }
        tabsShown = shown
        controller?.setToolbarItems(shown ? [foot.newTab, foot.tabs] : [foot.newTab], animated: false)
    }
}
