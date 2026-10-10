import Combine
import PadCore
import SwiftUI
import UIKit

/// The tabs, sharing the row as Safari's do: each as wide as the others,
/// down to a width where their names still read, past which the row
/// scrolls. The pinned tabs first, as icons; a split's two tabs as one, on a
/// shared ground.
///
/// In the compact layout the address field grows out of the tab on screen
/// the way Safari's does: the field takes the tab's place and widens over
/// the row, the tabs under it hidden rather than seen through its glass;
/// Return, Escape or a click on the page takes it back the same way.
///
/// UIKit, in a model of SwiftUI bars, because a tab is a pointer's thing:
/// a right-click opens its menu and a click goes to it (a tap recognizer
/// answers the primary button alone), the pointer's highlight takes the
/// tab's shape and follows the row as it scrolls, and the close button and
/// the star are controls of their own inside it, which UIKit keeps apart
/// from the tab's tap.
struct TabStripHost: UIViewRepresentable {
    @ObservedObject var session: Session
    @ObservedObject var model: WindowModel
    let compact: Bool
    let act: (BarAction) -> Void

    func makeUIView(context: Context) -> TabStripView {
        TabStripView(session: session, model: model, act: act)
    }

    func updateUIView(_ strip: TabStripView, context: Context) {
        strip.act = act
        strip.compact = compact
        strip.refresh()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TabStripView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: Metrics.bar)
    }
}

@MainActor
final class TabStripView: UIView {
    var act: (BarAction) -> Void
    var compact = true

    private let session: Session
    private let model: WindowModel
    private let scroller = UIScrollView()
    private let content = UIView()
    private var tabs: [UUID: TabView] = [:]
    private var grounds: [UIView] = []
    private let divider = UIView()
    private let field: AddressFieldView
    /// What the row showed last, to know when a change is worth animating.
    private var shown = ""
    private var animatesLayout = false
    private var editing = false

    init(session: Session, model: WindowModel, act: @escaping (BarAction) -> Void) {
        self.session = session
        self.model = model
        self.act = act
        field = AddressFieldView()
        super.init(frame: .zero)
        scroller.showsHorizontalScrollIndicator = false
        scroller.showsVerticalScrollIndicator = false
        scroller.clipsToBounds = true
        scroller.addSubview(content)
        addSubview(scroller)
        divider.backgroundColor = Palette.UI.hairline
        divider.layer.cornerRadius = 0.5
        content.addSubview(divider)
        field.isHidden = true
        field.submitted = { [weak self] text in self?.act(.go(text)) }
        field.typed = { [weak self] text in
            guard let self else { return }
            model.suggestions.typed(text, in: model)
        }
        field.ended = { [weak self] in
            guard let self, model.editingAddress else { return }
            act(.cancelAddress)
        }
        addSubview(field)
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: What the row shows

    /// The row as the workspace and the model have it now: tabs made,
    /// dropped and restyled, and the address field opened or closed.
    func refresh() {
        let space = session.workspace.space(model.spaceID)
        let row = TabRow(tabs: space?.tabs ?? [], splits: space?.splits ?? [], current: model.tabID,
                         compact: compact, addressRequired: model.addressRequired, width: bounds.width)
        let others = session.workspace.spaces.filter { $0.id != model.spaceID }
        var kept: Set<UUID> = []
        for tab in row.pinned + row.others {
            kept.insert(tab.id)
            let view = tabs[tab.id] ?? make(tab)
            let selected = tab.id == model.tabID
            let paired = row.paired.contains(tab.id)
            let beside = paired && row.splits.contains { $0.contains(tab.id) && model.tabID.map($0.contains) == true }
            view.tab = tab
            view.selected = selected
            view.onScreen = beside
            view.shape = tab.isPinned ? .whole : .half(meeting: row.seam(of: tab.id))
            view.face = row.width(of: tab) == nil ? .icon : compact && selected ? .current : .tab
            view.model = model
            view.menu = { [weak self] in self?.menu(for: tab, selected: selected, paired: paired, row: row, others: others) }
            view.restyle()
        }
        for (id, view) in tabs where !kept.contains(id) {
            tabs[id] = nil
            UIView.animate(springDuration: 0.3, bounce: 0, animations: { view.alpha = 0 }) { _ in view.removeFromSuperview() }
        }
        // Pinned state is part of the signature: pinning the first ordinary tab, or unpinning
        // the last pinned one, keeps the order and changes the tab's width.
        let signature = (row.pinned + row.others).map { $0.id.uuidString + ($0.isPinned ? "*" : "") }.joined()
            + "\(model.tabID?.uuidString ?? "")\(row.openPinned)\(compact)\(row.splits.map { "\($0.left)\($0.right)" }.joined())"
        if signature != shown {
            animatesLayout = !shown.isEmpty
            shown = signature
            setNeedsLayout()
        }
        let wants = compact && model.editingAddress && !model.phone
        if wants != editing {
            editing = wants
            if wants { openField() } else { closeField() }
        }
    }

    private func make(_ tab: TabRecord) -> TabView {
        let view = TabView()
        view.alpha = 0
        view.tapped = { [weak self] in
            guard let self, let view = tabs[tab.id] else { return }
            act(view.face == .current ? .editAddress : .select(tab.id))
        }
        view.closed = { [weak self] in self?.act(.close(tab.id)) }
        view.starred = { [weak self] in self?.act(.toggleBookmark) }
        view.reloaded = { [weak self] in
            guard let self else { return }
            act(model.loading ? .stop : .reload)
        }
        content.addSubview(view)
        tabs[tab.id] = view
        return view
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        scroller.frame = bounds
        let space = session.workspace.space(model.spaceID)
        let row = TabRow(tabs: space?.tabs ?? [], splits: space?.splits ?? [], current: model.tabID,
                         compact: compact, addressRequired: model.addressRequired, width: bounds.width)
        var frames: [UUID: CGRect] = [:]
        var groundFrames: [CGRect] = []
        let top = (bounds.height - Metrics.target) / 2
        var x: CGFloat = 0
        for tab in row.pinned {
            let width = row.width(of: tab) ?? Metrics.target
            frames[tab.id] = CGRect(x: x, y: top, width: width, height: Metrics.target)
            x += width + 2
        }
        let divided = !row.pinned.isEmpty && !row.others.isEmpty
        var dividerFrame = CGRect.zero
        if divided {
            dividerFrame = CGRect(x: x + 5, y: (bounds.height - 18) / 2, width: 1, height: 18)
            x += 11 + 2
        }
        for item in row.items {
            let start = x
            for tab in item.tabs {
                frames[tab.id] = CGRect(x: x, y: top, width: row.each, height: Metrics.target)
                x += row.each + 2
            }
            if item.tabs.count > 1 {
                groundFrames.append(CGRect(x: start, y: (bounds.height - Metrics.control) / 2, width: x - 2 - start,
                                           height: Metrics.control))
            }
        }
        let total = max(x - 2, 0)
        let animated = animatesLayout
        animatesLayout = false
        let place = {
            self.content.frame = CGRect(x: 0, y: 0, width: max(total, self.bounds.width), height: self.bounds.height)
            self.scroller.contentSize = CGSize(width: total, height: self.bounds.height)
            self.divider.frame = dividerFrame
            self.divider.alpha = divided ? 1 : 0
            for (id, view) in self.tabs {
                if let frame = frames[id] {
                    view.frame = frame
                    view.alpha = 1
                }
            }
        }
        // The grounds under splits: few, and flat, so made afresh each time.
        grounds.forEach { $0.removeFromSuperview() }
        grounds = groundFrames.map { frame in
            let ground = UIView(frame: frame)
            ground.backgroundColor = Palette.UI.shade
            ground.layer.cornerRadius = Metrics.control / 2
            ground.layer.cornerCurve = .continuous
            content.insertSubview(ground, at: 0)
            return ground
        }
        if animated {
            UIView.animate(springDuration: 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: place) { _ in self.scrollToCurrent(animated: true) }
        } else {
            place()
            scrollToCurrent(animated: false)
        }
        if editing { field.frame = fieldOpenFrame }
        updateMask()
    }

    private func scrollToCurrent(animated: Bool) {
        guard let id = model.tabID, let view = tabs[id], scroller.contentSize.width > scroller.bounds.width else { return }
        scroller.scrollRectToVisible(view.frame.insetBy(dx: -24, dy: 0), animated: animated)
    }

    // MARK: The address field

    /// The field's start and end: the tab on screen's place, kept inside the
    /// row for a tab half scrolled out of it; the whole row.
    private var fieldStartFrame: CGRect {
        guard let id = model.tabID, let view = tabs[id], view.frame.width > 0 else { return fieldOpenFrame }
        let tab = content.convert(view.frame, to: self)
        let minX = min(max(tab.minX, 0), bounds.width - Metrics.target)
        let maxX = max(min(tab.maxX, bounds.width), minX + Metrics.target)
        return CGRect(x: minX, y: 0, width: maxX - minX, height: bounds.height)
    }

    private var fieldOpenFrame: CGRect {
        bounds
    }

    private func openField() {
        layoutIfNeeded()
        model.suggestions.begin(at: model.url)
        field.begin(url: model.url, insecure: model.insecure)
        field.isHidden = false
        field.alpha = 1
        field.frame = fieldStartFrame
        field.layoutIfNeeded()
        updateMask()
        UIView.animate(springDuration: 0.3, bounce: 0, delay: 0.06, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.field.frame = self.fieldOpenFrame
            self.field.layoutIfNeeded()
            self.updateMask(duration: 0.3)
        }
    }

    private func closeField() {
        guard !field.isHidden else { return }
        field.end()
        UIView.animate(springDuration: 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.field.frame = self.fieldStartFrame
            self.field.layoutIfNeeded()
            self.updateMask(duration: 0.3)
        } completion: { _ in
            guard !self.editing else { return }
            self.field.isHidden = true
            self.updateMask()
        }
    }

    /// The tabs under the field are cut out of the row, not seen through
    /// its glass: a mask with the field's capsule taken out of it, moving
    /// with the field.
    private func updateMask(duration: TimeInterval = 0) {
        guard !field.isHidden else {
            scroller.layer.mask = nil
            return
        }
        let mask = (scroller.layer.mask as? CAShapeLayer) ?? {
            let layer = CAShapeLayer()
            layer.fillRule = .evenOdd
            scroller.layer.mask = layer
            return layer
        }()
        mask.frame = scroller.bounds
        let path = UIBezierPath(rect: scroller.bounds)
        path.append(UIBezierPath(roundedRect: field.capsuleFrame(in: scroller), cornerRadius: Metrics.control / 2))
        if duration > 0 {
            let spring = CASpringAnimation(perceptualDuration: duration, bounce: 0)
            spring.keyPath = "path"
            spring.fromValue = mask.presentation()?.path ?? mask.path
            spring.toValue = path.cgPath
            mask.add(spring, forKey: "path")
        }
        mask.path = path.cgPath
    }

    // MARK: Menus

    private func menu(for tab: TabRecord, selected: Bool, paired: Bool, row: TabRow, others: [Space]) -> UIMenu {
        var sections: [UIMenu] = []
        let page = compact ? selected && row.width(of: tab) != nil || selected : selected
        if page {
            var items: [UIAction] = []
            if model.url != nil {
                items.append(UIAction(title: "Share Page…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.act(.command(.share))
                })
                items.append(UIAction(title: model.bookmarked ? "Remove Bookmark" : "Bookmark This Page",
                                      image: UIImage(systemName: model.bookmarked ? "star.slash" : "star")) { [weak self] _ in
                    self?.act(.toggleBookmark)
                })
            }
            if let blocking = model.blocking {
                items.append(UIAction(title: blocking ? "Allow Ads on This Site" : "Block Ads on This Site",
                                      image: UIImage(systemName: blocking ? "shield.slash" : "shield")) { [weak self] _ in
                    self?.act(.command(.contentBlocking))
                })
            }
            if !items.isEmpty { sections.append(UIMenu(options: .displayInline, children: items)) }
        }
        var own: [UIMenuElement] = []
        if tab.isPinned {
            own.append(UIAction(title: "Back to Pinned Page", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                self?.act(.backToPinned(tab.id))
            })
            own.append(UIAction(title: "Unpin Tab", image: UIImage(systemName: "pin.slash")) { [weak self] _ in
                self?.act(.unpin(tab.id))
            })
        } else {
            own.append(UIAction(title: "Pin Tab", image: UIImage(systemName: "pin"),
                                attributes: tab.url == nil ? .disabled : []) { [weak self] _ in
                self?.act(.pin(tab.id))
            })
            if paired {
                own.append(UIAction(title: "Separate Tabs", image: UIImage(systemName: "rectangle")) { [weak self] _ in
                    self?.act(.separate(tab.id))
                })
                own.append(UIAction(title: "Swap Sides", image: UIImage(systemName: "arrow.left.arrow.right")) { [weak self] _ in
                    self?.act(.swapSides(tab.id))
                })
            } else if selected {
                own.append(UIAction(title: "Split with New Tab", image: UIImage(systemName: "rectangle.split.2x1")) { [weak self] _ in
                    self?.act(.splitWithNewTab)
                })
            } else if row.current.map({ !$0.isPinned }) == true {
                own.append(UIAction(title: "Open in Split View", image: UIImage(systemName: "rectangle.split.2x1")) { [weak self] _ in
                    self?.act(.splitWith(tab.id))
                })
            }
        }
        sections.append(UIMenu(options: .displayInline, children: own))
        var away: [UIMenuElement] = [
            UIAction(title: "Close Tab", image: UIImage(systemName: "xmark")) { [weak self] _ in self?.act(.close(tab.id)) },
            UIAction(title: "Open in New Window", image: UIImage(systemName: "macwindow.badge.plus")) { [weak self] _ in
                self?.act(.tabInNewWindow(tab.id))
            },
        ]
        if !others.isEmpty {
            away.append(UIMenu(title: "Move to Space", image: UIImage(systemName: "arrow.right.square"), children: others.map { space in
                UIAction(title: space.name, image: UIImage(systemName: space.symbol)) { [weak self] _ in
                    self?.act(.moveTab(tab.id, space.id))
                }
            }))
        }
        sections.append(UIMenu(options: .displayInline, children: away))
        if selected {
            sections.append(UIMenu(options: .displayInline, children: [
                UIAction(title: "Command Palette", image: UIImage(systemName: "command")) { [weak self] _ in self?.act(.command(.palette)) },
                UIAction(title: "Settings", image: UIImage(systemName: "gearshape")) { [weak self] _ in self?.act(.command(.settings)) },
            ]))
        }
        return UIMenu(children: sections)
    }
}

// MARK: A tab

/// One tab in the row: its icon and its name, or its icon alone when
/// pinned; on screen, in the compact layout, where it is and the star and
/// reload beside, and a click on it types a new address.
@MainActor
final class TabView: UIView, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
    enum Face {
        /// A pinned tab: its icon alone.
        case icon
        /// Its icon and its name.
        case tab
        /// The tab on screen in the compact layout: where it is, the key
        /// badge, the star and reload.
        case current
    }

    var tab = TabRecord(id: UUID(), url: nil, title: "")
    var selected = false
    /// On screen beside the tab with the keys, in its split.
    var onScreen = false
    var shape = TabShape.whole
    var face = Face.tab
    weak var model: WindowModel?
    var menu: (() -> UIMenu?)?
    var tapped: (() -> Void)?
    var closed: (() -> Void)?
    var starred: (() -> Void)?
    var reloaded: (() -> Void)?

    private let surface: UIView
    private let icon = SiteIconUIView()
    private let warning = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
    private let close = PressButton(symbol: "xmark", size: 9, weight: .bold, hover: .circle(3))
    private let name = UILabel()
    private let badge = UIView()
    private let key = UIImageView(image: UIImage(systemName: "key.fill"))
    private let star = PressButton(symbol: "star", size: 13, weight: .medium, hover: .rounded(3))
    private let reload = PressButton(symbol: "arrow.clockwise", size: 12, weight: .semibold, hover: .rounded(3))
    private var hovering = false
    private var cancellables: Set<AnyCancellable> = []

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = false
            surface = UIVisualEffectView(effect: glass)
        } else {
            surface = UIView()
            surface.backgroundColor = Palette.UI.wash
        }
        super.init(frame: frame)
        addSubview(surface)
        warning.tintColor = Palette.UI.unsafe
        warning.contentMode = .center
        warning.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11)
        addSubview(icon)
        addSubview(warning)
        close.tintColor = Palette.UI.muted
        close.accessibilityLabel = "Close Tab"
        close.addAction(UIAction { [weak self] _ in self?.closed?() }, for: .primaryActionTriggered)
        addSubview(close)
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        addSubview(name)
        badge.backgroundColor = Palette.UI.wash
        badge.layer.cornerRadius = 11
        key.tintColor = Palette.UI.muted
        key.contentMode = .center
        key.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        badge.addSubview(key)
        badge.accessibilityLabel = "Sign-in page"
        addSubview(badge)
        star.tintColor = Palette.UI.muted
        star.addAction(UIAction { [weak self] _ in self?.starred?() }, for: .primaryActionTriggered)
        addSubview(star)
        reload.tintColor = Palette.UI.ink
        reload.addAction(UIAction { [weak self] _ in self?.reloaded?() }, for: .primaryActionTriggered)
        addSubview(reload)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hover(_:)))
        addGestureRecognizer(hover)
        addInteraction(UIContextMenuInteraction(delegate: self))
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// What it shows, from the tab, the model and its place in the row.
    func restyle() {
        let current = face == .current
        let url = current ? model?.url ?? tab.url : tab.url
        let showsAddress = current && model?.showsAddress == true
        let insecure = current && model?.insecure == true
        surface.isHidden = !selected
        icon.url = face == .icon ? tab.pinned ?? tab.url : current ? url : tab.url
        icon.size = face == .icon ? 18 : 16
        let closes = face == .tab && (selected || hovering) || current && !tab.isPinned
        close.isHidden = !closes
        warning.isHidden = !(showsAddress && insecure)
        icon.isHidden = closes || !warning.isHidden
        name.isHidden = face == .icon
        if current && showsAddress {
            name.attributedText = addressText(url, hostOnly: true, size: 13)
            name.lineBreakMode = .byTruncatingHead
        } else {
            name.attributedText = nil
            name.text = current ? (model?.title.isEmpty == false ? model?.title : tab.label) : tab.label
            name.font = .systemFont(ofSize: 13, weight: selected ? .medium : .regular)
            name.textColor = selected || onScreen ? Palette.UI.ink : Palette.UI.muted
            name.lineBreakMode = .byTruncatingTail
        }
        let tools = current && TabView.roomy(bounds.width) && url != nil
        badge.isHidden = !(tools && model?.signIn == true)
        star.isHidden = !tools
        reload.isHidden = !tools
        star.setImage(UIImage(systemName: model?.bookmarked == true ? "star.fill" : "star"), for: .normal)
        star.tintColor = model?.bookmarked == true ? Palette.UI.ink : Palette.UI.muted
        star.accessibilityLabel = model?.bookmarked == true ? "Remove Bookmark" : "Bookmark This Page"
        reload.setImage(UIImage(systemName: model?.loading == true ? "xmark" : "arrow.clockwise"), for: .normal)
        reload.accessibilityLabel = model?.loading == true ? "Stop" : "Reload"
        applyShape()
        if current {
            accessibilityLabel = url.map { "Address, \(Destination.pretty($0))" } ?? "Address"
            accessibilityHint = "Type a new address or a search"
        } else {
            accessibilityLabel = tab.isPinned ? "\(tab.label), pinned" : tab.label
            accessibilityHint = nil
        }
        accessibilityTraits = selected ? [.button, .selected] : .button
        setNeedsLayout()
    }

    /// Room for the star and reload as well as a name that reads.
    static func roomy(_ width: CGFloat) -> Bool {
        width >= 200
    }

    private var surfaceFrame: CGRect {
        CGRect(x: 0, y: (bounds.height - Metrics.control) / 2, width: bounds.width, height: Metrics.control)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let box = surfaceFrame
        surface.frame = box
        let tools = !star.isHidden
        if face == .icon {
            icon.frame = CGRect(x: (bounds.width - icon.size) / 2, y: box.midY - icon.size / 2, width: icon.size, height: icon.size)
        } else {
            let slot = CGRect(x: TabFace.lead, y: box.minY, width: TabFace.slot, height: Metrics.control)
            icon.frame = CGRect(x: slot.midX - icon.size / 2, y: slot.midY - icon.size / 2, width: icon.size, height: icon.size)
            warning.frame = slot
            close.frame = slot
            var right = bounds.width - (tools ? 2 : 10)
            if tools {
                reload.frame = CGRect(x: right - 30, y: box.minY, width: 30, height: Metrics.control)
                right -= 30
                star.frame = CGRect(x: right - 30, y: box.minY, width: 30, height: Metrics.control)
                right -= 30
                if !badge.isHidden {
                    badge.frame = CGRect(x: right - 24 - 2, y: box.midY - 11, width: 24, height: 22)
                    key.frame = badge.bounds
                    right -= 28
                }
            }
            let left = slot.maxX + TabFace.gap
            name.frame = CGRect(x: left, y: box.minY, width: max(0, right - 4 - left), height: Metrics.control)
        }
        hoverStyle = UIHoverStyle(effect: .highlight, shape: hoverShape(in: box))
        let tools2 = face == .current && TabView.roomy(bounds.width) && (model?.url ?? tab.url) != nil
        if tools2 != tools { restyle() }
    }

    private func applyShape() {
        if #available(iOS 26.0, *) {
            let seam = UICornerRadius.fixed(shape.joined)
            let round = UICornerRadius.fixed(Metrics.control / 2)
            surface.cornerConfiguration = shape.joined >= Metrics.control / 2 ? .capsule()
                : shape.leading ? .corners(topLeftRadius: seam, topRightRadius: round, bottomLeftRadius: seam, bottomRightRadius: round)
                : .corners(topLeftRadius: round, topRightRadius: seam, bottomLeftRadius: round, bottomRightRadius: seam)
        } else {
            surface.layer.cornerRadius = Metrics.control / 2
            surface.layer.cornerCurve = .continuous
            // The seam's small radius is squared off before iPadOS 26: a
            // layer rounds all its corners alike.
            surface.layer.maskedCorners = shape.joined >= Metrics.control / 2 ? [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
                : shape.leading ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
    }

    private func hoverShape(in box: CGRect) -> UIShape {
        guard shape.joined < Metrics.control / 2 else { return .fixedRect(box, cornerRadius: Metrics.control / 2, cornerCurve: .continuous) }
        let corners: UIRectCorner = shape.leading ? [.topRight, .bottomRight] : [.topLeft, .bottomLeft]
        return .fixedRect(box, cornerRadius: Metrics.control / 2, cornerCurve: .continuous, maskedCorners: corners)
    }

    private func shapePath(in box: CGRect) -> UIBezierPath {
        let round = Metrics.control / 2
        let seam = min(max(shape.joined, 0), round)
        let corners: UIRectCorner = seam >= round ? .allCorners : shape.leading ? [.topRight, .bottomRight] : [.topLeft, .bottomLeft]
        let path = UIBezierPath(roundedRect: box, byRoundingCorners: corners, cornerRadii: CGSize(width: round, height: round))
        return path
    }

    // MARK: Pointer and touch

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        tapped?()
    }

    @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
        let now = recognizer.state == .began || recognizer.state == .changed
        guard now != hovering else { return }
        hovering = now
        if face == .tab && !selected { restyle() }
    }

    /// A touch on a button inside is the button's; the tab's tap stays out of it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menu else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu() }
    }

    /// The menu lifts the tab in its own shape, not the box around it.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        let parameters = UIPreviewParameters()
        parameters.visiblePath = shapePath(in: surfaceFrame)
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: self, parameters: parameters)
    }
}

// MARK: The address field

/// The compact layout's address field: the tab on screen's glass, carried
/// out over the row while an address is typed. It opens with the address
/// selected, so typing replaces it; Return goes, and losing the keys
/// (Escape, a click on the page) leaves the page as it was.
@MainActor
final class AddressFieldView: UIView, UITextFieldDelegate {
    var submitted: ((String) -> Void)?
    /// What the field holds, as it changes, for the suggestions under it.
    var typed: ((String) -> Void)?
    var ended: (() -> Void)?

    private let glass: UIView
    private let icon = SiteIconUIView()
    private let warning = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
    private let search = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let text = UITextField()
    private let clear = PressButton(symbol: "xmark.circle.fill", size: 14, weight: .regular, hover: .rounded(3))

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect()
            effect.isInteractive = false
            glass = UIVisualEffectView(effect: effect)
            glass.cornerConfiguration = .capsule()
        } else {
            glass = UIView()
            glass.backgroundColor = Palette.UI.wash
            glass.layer.cornerRadius = Metrics.control / 2
            glass.layer.cornerCurve = .continuous
        }
        super.init(frame: frame)
        addSubview(glass)
        icon.size = 16
        addSubview(icon)
        warning.tintColor = Palette.UI.unsafe
        warning.contentMode = .center
        warning.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12)
        addSubview(warning)
        search.tintColor = Palette.UI.muted
        search.contentMode = .center
        search.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        addSubview(search)
        text.placeholder = "Address or search"
        text.font = .systemFont(ofSize: 13)
        text.textColor = Palette.UI.ink
        text.keyboardType = .webSearch
        text.autocapitalizationType = .none
        text.autocorrectionType = .no
        text.spellCheckingType = .no
        text.returnKeyType = .go
        text.delegate = self
        text.addTarget(self, action: #selector(changed), for: .editingChanged)
        addSubview(text)
        clear.tintColor = Palette.UI.faint
        clear.accessibilityLabel = "Clear"
        clear.addAction(UIAction { [weak self] _ in
            self?.text.text = ""
            self?.changed()
        }, for: .primaryActionTriggered)
        addSubview(clear)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The glass, in the row's coordinates: what the row's mask leaves out.
    func capsuleFrame(in view: UIView) -> CGRect {
        convert(glass.frame, to: view)
    }

    /// The tab's address, all of it selected, with the keys.
    func begin(url: URL?, insecure: Bool) {
        text.text = url.map(Destination.editable) ?? ""
        icon.url = url
        icon.isHidden = url == nil || insecure
        warning.isHidden = !insecure
        search.isHidden = url != nil
        changed()
        _ = text.becomeFirstResponder()
        // The field's own selection: sent to no one in particular, select
        // all reached the page when it still had the keys.
        DispatchQueue.main.async { [weak self] in
            guard let self, text.isFirstResponder else { return }
            text.selectAll(nil)
        }
    }

    func end() {
        if text.isFirstResponder { _ = text.resignFirstResponder() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let box = CGRect(x: 0, y: (bounds.height - Metrics.control) / 2, width: bounds.width, height: Metrics.control)
        glass.frame = box
        let slot = CGRect(x: TabFace.lead, y: box.minY, width: TabFace.slot, height: Metrics.control)
        icon.frame = CGRect(x: slot.midX - 8, y: slot.midY - 8, width: 16, height: 16)
        warning.frame = slot
        search.frame = slot
        let right = bounds.width - 2
        clear.frame = CGRect(x: right - 30, y: box.minY, width: 30, height: Metrics.control)
        let end = clear.isHidden ? right - 8 : right - 30
        text.frame = CGRect(x: slot.maxX + TabFace.gap, y: box.minY, width: max(0, end - slot.maxX - TabFace.gap), height: Metrics.control)
    }

    @objc private func changed() {
        typed?(text.text ?? "")
        let empty = text.text?.isEmpty ?? true
        guard clear.isHidden != empty else { return }
        clear.isHidden = empty
        setNeedsLayout()
    }

    func textFieldShouldReturn(_ field: UITextField) -> Bool {
        // What is still being composed is part of what Return sends.
        field.unmarkText()
        submitted?(field.text ?? "")
        return false
    }

    func textFieldDidEndEditing(_ field: UITextField) {
        ended?()
    }
}

// MARK: Pieces

/// A button on a bar or in a tab: a symbol that gives a little while held,
/// with the pointer's highlight in the shape it is drawn in.
final class PressButton: UIButton {
    enum Hover {
        case circle(CGFloat)
        case rounded(CGFloat)
    }

    private let hover: Hover

    init(symbol: String, size: CGFloat, weight: UIImage.SymbolWeight, hover: Hover) {
        self.hover = hover
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        self.configuration = configuration
        setImage(UIImage(systemName: symbol), for: .normal)
        setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: size, weight: weight), forImageIn: .normal)
        configurationUpdateHandler = { button in
            UIView.animate(springDuration: 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                button.transform = button.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch hover {
        case .circle(let inset):
            let side = min(bounds.width, bounds.height) - inset * 2
            let box = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            hoverStyle = UIHoverStyle(effect: .highlight, shape: .fixedRect(box, cornerRadius: side / 2))
        case .rounded(let inset):
            hoverStyle = UIHoverStyle(effect: .highlight,
                                      shape: .fixedRect(bounds.insetBy(dx: inset, dy: inset), cornerRadius: Metrics.corner, cornerCurve: .continuous))
        }
    }
}

/// A site's icon as SiteIcons has it, or its first letter on a colour of
/// its own until it does: SiteIconView, for UIKit.
@MainActor
final class SiteIconUIView: UIView {
    var url: URL? {
        didSet { if url != oldValue { refresh() } }
    }

    var size: CGFloat = 16 {
        didSet { if size != oldValue { setNeedsLayout() } }
    }

    private let image = UIImageView()
    private let letter = UILabel()
    private var watching: AnyCancellable?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerCurve = .continuous
        // No outline: a site's icon already has its own shape, often a
        // rounded square or a mark on nothing, and a second edge around it
        // reads as a frame.
        image.contentMode = .scaleAspectFit
        addSubview(image)
        letter.textAlignment = .center
        letter.textColor = .white
        addSubview(letter)
        isAccessibilityElement = false
        watching = SiteIcons.shared.$revision.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = size * 0.225
        image.frame = bounds
        letter.frame = bounds
        letter.font = .systemFont(ofSize: size * 0.56, weight: .semibold).rounded
    }

    private func refresh() {
        if let found = SiteIcons.shared.image(for: url) {
            image.image = found
            image.isHidden = false
            letter.isHidden = true
            backgroundColor = .clear
        } else {
            image.isHidden = true
            letter.isHidden = false
            letter.text = host.first.map { String($0).uppercased() } ?? "•"
            backgroundColor = letterColor
        }
    }

    private var host: String {
        guard let host = url?.host() else { return "" }
        return Destination.registrable(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }

    /// The same colour for a site every time: from its name, not at random.
    private var letterColor: UIColor {
        let palette: [SpaceColor] = [.blue, .purple, .pink, .red, .orange, .green, .teal, .indigo]
        let sum = host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count].uiColor
    }
}

private extension UIFont {
    var rounded: UIFont {
        fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}

/// "accounts." muted, "google.com" in bold, "/v3/signin" muted: the part of
/// the host that says who you are talking to stands out (AddressLine).
@MainActor
func addressText(_ url: URL?, hostOnly: Bool, size: CGFloat) -> NSAttributedString {
    let plain = UIFont.systemFont(ofSize: size)
    let bold = UIFont.systemFont(ofSize: size, weight: .semibold)
    guard let url, let host = url.host() else {
        return NSAttributedString(string: "Address or search", attributes: [.font: plain, .foregroundColor: Palette.UI.muted])
    }
    let bare = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let full = Destination.pretty(url)
    let pretty = hostOnly && full.hasPrefix(bare) ? bare : full
    let name = Destination.registrable(bare)
    guard pretty.hasPrefix(bare), bare.hasSuffix(name) else {
        return NSAttributedString(string: pretty, attributes: [.font: plain, .foregroundColor: Palette.UI.ink])
    }
    let sub = String(bare.dropLast(name.count))
    let rest = String(pretty.dropFirst(bare.count))
    let text = NSMutableAttributedString(string: sub, attributes: [.font: plain, .foregroundColor: Palette.UI.muted])
    text.append(NSAttributedString(string: name, attributes: [.font: bold, .foregroundColor: Palette.UI.ink]))
    text.append(NSAttributedString(string: rest, attributes: [.font: plain, .foregroundColor: Palette.UI.muted]))
    return text
}

// MARK: The row's arithmetic

/// The row's tabs, and how wide each is.
struct TabRow {
    let pinned: [TabRecord]
    let others: [TabRecord]
    let splits: [Split]
    /// The ordinary tabs as the row shows them: one at a time, or a split's
    /// two together.
    let items: [TabItem]
    /// The tabs in a split.
    let paired: Set<UUID>
    let current: TabRecord?
    /// A tab's width; a pinned tab is its icon.
    let each: CGFloat
    /// The pinned tab on screen must say where it is (a sign-in page), so
    /// it opens up to a tab's width. Otherwise it stays an icon, so going to
    /// it moves nothing in the row: you pinned it, you know where it is, and
    /// a click on it shows the address.
    let openPinned: Bool

    /// The narrowest a tab gets: its name still reads.
    private static let narrowest: CGFloat = 120

    init(tabs: [TabRecord], splits: [Split], current id: UUID?, compact: Bool, addressRequired: Bool, width: CGFloat) {
        let ordinary = tabs.filter { !$0.isPinned }
        pinned = tabs.filter(\.isPinned)
        others = ordinary
        self.splits = splits
        paired = Set(splits.flatMap { [$0.left, $0.right] })
        var items: [TabItem] = []
        var index = 0
        while index < ordinary.count {
            let tab = ordinary[index]
            let next = index + 1 < ordinary.count ? ordinary[index + 1].id : nil
            if let next, splits.contains(where: { $0.left == tab.id && $0.right == next }) {
                items.append(TabItem(tabs: [tab, ordinary[index + 1]]))
                index += 2
            } else {
                items.append(TabItem(tabs: [tab]))
                index += 1
            }
        }
        self.items = items
        current = tabs.first { $0.id == id }
        openPinned = compact && addressRequired && current?.isPinned == true
        let icons = pinned.count - (openPinned ? 1 : 0)
        let shares = others.count + (openPinned ? 1 : 0)
        let divided = !pinned.isEmpty && !others.isEmpty
        // The row's 2-point gaps fall between its pieces: the icons, the
        // divider (1 point and 5 either side) and the tabs.
        let pieces = icons + shares + (divided ? 1 : 0)
        let room = width - CGFloat(icons) * Metrics.target - (divided ? 11 : 0) - CGFloat(max(pieces - 1, 0)) * 2
        let even = shares == 0 ? 0 : (room / CGFloat(shares)).rounded(.down)
        // Compact tabs fill the row, as Safari's do; separate ones stop where a name has room.
        each = compact ? max(even, Self.narrowest) : min(max(even, Self.narrowest), 280)
    }

    /// The end of a split's half that meets the other half: the left
    /// one's trailing end, the right one's leading end; nil out of a split.
    func seam(of tab: UUID) -> HorizontalEdge? {
        guard let split = splits.first(where: { $0.contains(tab) }) else { return nil }
        return split.left == tab ? .trailing : .leading
    }

    /// Nil for a pinned tab's icon alone.
    func width(of tab: TabRecord) -> CGFloat? {
        tab.isPinned && !(openPinned && tab.id == current?.id) ? nil : each
    }
}

/// One tab of the row, or a split's two shown as one.
struct TabItem: Identifiable {
    let tabs: [TabRecord]

    var id: UUID {
        tabs.first?.id ?? UUID()
    }
}
