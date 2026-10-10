import Combine
import PadCore
import UIKit

/// The space's tabs as a grid, on the sheet the phone bar turns into
/// (TabSheet), as Safari and Comet show theirs: each tab as a picture of its
/// page with its name under it, then the space's tabs on other devices. The
/// pinned tabs sit apart, in a dock at the bottom as the iPhone's apps do,
/// their icons scrolling sideways when there are more than fit. A tap goes to a tab; a swipe sideways
/// throws it away and closes it; a long press has Safari's menu (copy,
/// share, pin, move, arrange, close others, close all). New Tab and Done
/// are at the bottom, where the thumb already is.
///
/// UIKit, because a card that follows a finger sideways inside a list that
/// scrolls up and down is a matter of which gesture gets the touch, and
/// UIKit lets each one say.
@MainActor
final class TabOverviewController: UIViewController, UICollectionViewDelegate {
    private enum Section: Hashable {
        case tabs
        /// Another device's open tabs in this space, by its record's name.
        case device(String)
    }

    private enum Item: Hashable {
        case tab(UUID)
        case remote(String, Int)
    }

    private let session: Session
    private let window: WindowModel
    private let act: (BarAction) -> Void
    private let done: (BarAction?) -> Void

    private let header = UIView()
    private let symbol = UIImageView()
    private let heading = UILabel()
    private var collection: UICollectionView!
    private var source: UICollectionViewDiffableDataSource<Section, Item>!
    private let dock = PinnedDock()
    private let newTab = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    private var previews: [UUID: UIImage] = [:]
    private var asked: Set<UUID> = []
    private var watching: Set<AnyCancellable> = []
    private var applying = false
    private var shown = false
    private var scrolledToCurrent = false

    private static let headerHeight: CGFloat = 52
    private static let barHeight: CGFloat = 64

    init(session: Session, window: WindowModel, act: @escaping (BarAction) -> Void, done: @escaping (BarAction?) -> Void) {
        self.session = session
        self.window = window
        self.act = act
        self.done = done
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.UI.tray

        symbol.contentMode = .center
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.textColor = Palette.UI.ink
        header.addSubview(symbol)
        header.addSubview(heading)
        header.isAccessibilityElement = true
        header.accessibilityTraits = .header

        collection = UICollectionView(frame: .zero, collectionViewLayout: layout())
        collection.backgroundColor = .clear
        collection.contentInsetAdjustmentBehavior = .never
        collection.alwaysBounceVertical = true
        collection.delegate = self
        view.addSubview(collection)
        view.addSubview(header)

        newTab.configuration = Self.glass(symbol: "plus")
        newTab.accessibilityLabel = "New Tab"
        newTab.addAction(UIAction { [weak self] _ in self?.done(.command(.newTab)) }, for: .primaryActionTriggered)
        doneButton.configuration = Self.glass(title: "Done")
        doneButton.addAction(UIAction { [weak self] _ in self?.done(nil) }, for: .primaryActionTriggered)
        dock.chosen = { [weak self] id in self?.done(.select(id)) }
        dock.menu = { [weak self] tab, source in self?.menu(for: tab, from: source) }
        view.addSubview(dock)
        view.addSubview(newTab)
        view.addSubview(doneButton)

        makeSource()
        apply()
        session.$workspace.sink { [weak self] _ in self?.applySoon() }.store(in: &watching)
        window.$tabID.sink { [weak self] _ in self?.applySoon() }.store(in: &watching)
        window.$spaceID.sink { [weak self] _ in self?.applySoon() }.store(in: &watching)
        Sync.shared.$elsewhere.sink { [weak self] _ in self?.applySoon() }.store(in: &watching)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        heading.sizeToFit()
        let width = min(heading.bounds.width, bounds.width - 80)
        let total = 20 + 6 + width
        symbol.frame = CGRect(x: (bounds.width - total) / 2, y: 0, width: 20, height: Self.headerHeight)
        heading.frame = CGRect(x: symbol.frame.maxX + 6, y: 0, width: width, height: Self.headerHeight)
        collection.frame = CGRect(x: 0, y: Self.headerHeight, width: bounds.width, height: max(0, bounds.height - Self.headerHeight))
        let y = bounds.height - Self.barHeight + 10
        let docked = !dock.isHidden
        dock.frame = CGRect(x: 12, y: bounds.height - Self.barHeight - PinnedDock.height + 2, width: bounds.width - 24,
                            height: PinnedDock.height)
        // The grid's last row clears the dock, which floats over the grid
        // as it scrolls, with room to spare.
        let below = Self.barHeight + (docked ? PinnedDock.height + 20 : 8)
        collection.contentInset.bottom = below
        collection.verticalScrollIndicatorInsets.bottom = below
        newTab.frame = CGRect(x: 16, y: y, width: 44, height: 44)
        let fits = doneButton.sizeThatFits(CGSize(width: 200, height: 44))
        doneButton.frame = CGRect(x: bounds.width - 16 - max(fits.width, 72), y: y, width: max(fits.width, 72), height: 44)
        // The tab on screen in the middle, once there is a grid to put it in.
        if !scrolledToCurrent, collection.bounds.height > 0, let current = window.tabID,
           let path = source.indexPath(for: .tab(current)) {
            scrolledToCurrent = true
            collection.layoutIfNeeded()
            collection.scrollToItem(at: path, at: .centeredVertically, animated: false)
        }
    }

    private static func glass(symbol: String? = nil, title: String? = nil) -> UIButton.Configuration {
        var style: UIButton.Configuration
        if #available(iOS 26.0, *) {
            style = .glass()
        } else {
            style = .gray()
        }
        style.cornerStyle = .capsule
        style.baseForegroundColor = Palette.UI.ink
        if let symbol {
            style.image = UIImage(systemName: symbol)
            style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            style.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        }
        if let title {
            style.title = title
            style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 17, weight: .semibold)
                return attributes
            }
            style.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        }
        return style
    }

    // MARK: The grid

    private func layout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self, let section = source?.sectionIdentifier(for: index) else { return nil }
            let width = environment.container.effectiveContentSize.width
            switch section {
            case .tabs:
                let inner = width - 32
                let columns = max(2, Int((inner + 14) / (150 + 14)))
                let cardWidth = ((inner - CGFloat(columns - 1) * 14) / CGFloat(columns)).rounded(.down)
                let height = TabCardCell.height(forWidth: cardWidth)
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(cardWidth), heightDimension: .absolute(height)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                                 heightDimension: .absolute(height)),
                                                               repeatingSubitem: item, count: columns)
                group.interItemSpacing = .fixed(14)
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 18
                section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                return section
            case .device:
                var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
                list.backgroundColor = .clear
                list.headerMode = .supplementary
                return NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            }
        }
    }

    private func makeSource() {
        let card = UICollectionView.CellRegistration<TabCardCell, UUID> { [weak self] cell, _, id in
            self?.configure(cell, id)
        }
        let remote = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
            guard let self, case .remote(let device, let index) = item, let tab = remoteTab(device, index) else { return }
            var content = UIListContentConfiguration.subtitleCell()
            let url = URL(string: tab.url)
            content.text = tab.title.isEmpty ? url.map(Destination.pretty) ?? tab.url : tab.title
            content.secondaryText = url.map(Destination.pretty) ?? tab.url
            content.textProperties.font = .systemFont(ofSize: 14, weight: .medium)
            content.textProperties.numberOfLines = 1
            content.secondaryTextProperties.color = Palette.UI.muted
            content.secondaryTextProperties.numberOfLines = 1
            content.image = SiteIcons.shared.image(for: url) ?? UIImage(systemName: "globe")
            content.imageProperties.maximumSize = CGSize(width: 20, height: 20)
            content.imageProperties.cornerRadius = 4.5
            content.imageProperties.tintColor = Palette.UI.muted
            cell.contentConfiguration = content
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = Palette.UI.card
            cell.backgroundConfiguration = background
            cell.accessories = tab.pinned ? [.customView(configuration: .init(customView: UIImageView(image: UIImage(systemName: "pin.fill")),
                                                                              placement: .trailing()))] : []
        }
        source = UICollectionViewDiffableDataSource(collectionView: collection) { view, path, item in
            switch item {
            case .tab(let id): return view.dequeueConfiguredReusableCell(using: card, for: path, item: id)
            case .remote: return view.dequeueConfiguredReusableCell(using: remote, for: path, item: item)
            }
        }
        let heading = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, path in
            guard let self, case .device(let id) = source.sectionIdentifier(for: path.section),
                  let device = Sync.shared.elsewhere.first(where: { $0.id == id }) else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = "\(device.browser) · \(device.deviceName)"
            content.image = UIImage(systemName: device.browser == "Safience" ? "iphone" : "laptopcomputer")
            view.contentConfiguration = content
        }
        source.supplementaryViewProvider = { view, kind, path in
            view.dequeueConfiguredReusableSupplementary(using: heading, for: path)
        }
    }

    private var space: Space? {
        session.workspace.space(window.spaceID)
    }

    private var spaceColor: UIColor {
        space?.color.uiColor ?? Palette.UI.ink
    }

    private var devices: [SyncDeviceTabs] {
        let cloud = space?.cloudID?.uuidString
        return Sync.shared.elsewhere.filter { $0.space == cloud }
    }

    private func remoteTab(_ device: String, _ index: Int) -> SyncTab? {
        guard let found = Sync.shared.elsewhere.first(where: { $0.id == device }), found.tabs.indices.contains(index) else { return nil }
        return found.tabs[index]
    }

    private func configure(_ cell: TabCardCell, _ id: UUID) {
        guard let tab = session.workspace.tab(id) else { return }
        // As each card comes into view, so a space of many tabs never holds every picture.
        if previews[id] == nil, tab.url != nil, !asked.contains(id) {
            asked.insert(id)
            session.pages.preview(for: id, width: Pages.previewWidth) { [weak self] image in
                guard let self, let image else { return }
                previews[id] = image
                var snapshot = source.snapshot()
                if snapshot.itemIdentifiers.contains(.tab(id)) {
                    snapshot.reconfigureItems([.tab(id)])
                    source.apply(snapshot, animatingDifferences: false)
                }
            }
        }
        cell.configure(tab: tab, image: previews[id], current: id == window.tabID, color: spaceColor)
        cell.closed = { [weak self] in self?.act(.close(id)) }
    }

    private func applySoon() {
        guard !applying else { return }
        applying = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            applying = false
            apply()
        }
    }

    private func apply() {
        guard source != nil else { return }
        let tabs = space?.tabs ?? []
        let pinned = tabs.filter(\.isPinned)
        let others = tabs.filter { !$0.isPinned }
        symbol.image = UIImage(systemName: space?.symbol ?? "square.grid.2x2")
        symbol.tintColor = spaceColor
        heading.text = space?.name ?? "Tabs"
        header.accessibilityLabel = heading.text
        view.setNeedsLayout()

        dock.isHidden = pinned.isEmpty
        dock.show(pinned, current: window.tabID, color: spaceColor)

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.tabs])
        snapshot.appendItems(others.map { .tab($0.id) }, toSection: .tabs)
        for device in devices where !device.tabs.isEmpty {
            snapshot.appendSections([.device(device.id)])
            snapshot.appendItems(device.tabs.indices.map { .remote(device.id, $0) }, toSection: .device(device.id))
        }
        // What a card says (its name, the ring of the tab on screen) can
        // change without the card coming or going.
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        source.apply(snapshot, animatingDifferences: shown && !UIAccessibility.isReduceMotionEnabled)
        shown = true
    }

    // MARK: Taps and menus

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
        collectionView.deselectItem(at: path, animated: false)
        switch source.itemIdentifier(for: path) {
        case .tab(let id):
            done(.select(id))
        case .remote(let device, let index):
            if let tab = remoteTab(device, index), let url = URL(string: tab.url) { done(.openInNewTab(url)) }
        case nil:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt paths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = paths.first else { return nil }
        let id: UUID
        switch source.itemIdentifier(for: path) {
        case .tab(let tab): id = tab
        default: return nil
        }
        guard let tab = session.workspace.tab(id), let cell = collectionView.cellForItem(at: path) else { return nil }
        return UIContextMenuConfiguration(identifier: id.uuidString as NSString, previewProvider: nil) { [weak self] _ in
            self?.menu(for: tab, from: cell)
        }
    }

    /// The card lifts in its own rounded shape, not the box around it.
    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        highlightPreviewForItemAt path: IndexPath) -> UITargetedPreview? {
        (collectionView.cellForItem(at: path) as? TabCardCell)?.preview()
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        dismissalPreviewForItemAt path: IndexPath) -> UITargetedPreview? {
        self.collectionView(collectionView, contextMenuConfiguration: configuration, highlightPreviewForItemAt: path)
    }

    /// Safari's menu for a tab in its overview: its link, where it is kept,
    /// the order of them all, and closing it, the others or every one.
    private func menu(for tab: TabRecord, from source: UIView) -> UIMenu {
        var sections: [UIMenuElement] = []
        let address = tab.isPinned ? tab.url ?? tab.pinned : tab.url
        if let address {
            sections.append(UIMenu(options: .displayInline, children: [
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.url = address },
                UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.share(address, from: source)
                },
            ]))
        }
        var keep: [UIMenuElement] = []
        if tab.isPinned {
            keep.append(UIAction(title: "Back to Pinned Page", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                self?.act(.backToPinned(tab.id))
            })
            keep.append(UIAction(title: "Unpin Tab", image: UIImage(systemName: "pin.slash")) { [weak self] _ in
                self?.act(.unpin(tab.id))
            })
        } else if tab.url != nil {
            keep.append(UIAction(title: "Pin Tab", image: UIImage(systemName: "pin")) { [weak self] _ in self?.act(.pin(tab.id)) })
        }
        let others = session.workspace.spaces.filter { $0.id != window.spaceID }
        if !others.isEmpty {
            keep.append(UIMenu(title: "Move to Space", image: UIImage(systemName: "arrow.right.square"), children: others.map { space in
                UIAction(title: space.name, image: UIImage(systemName: space.symbol)) { [weak self] _ in
                    self?.act(.moveTab(tab.id, space.id))
                }
            }))
        }
        let ordinary = (space?.tabs ?? []).filter { !$0.isPinned }
        if ordinary.count > 1 {
            keep.append(UIMenu(title: "Arrange Tabs By", image: UIImage(systemName: "arrow.up.arrow.down"), children: [
                UIAction(title: "Title", image: UIImage(systemName: "textformat")) { [weak self] _ in self?.act(.arrangeTabs(.title)) },
                UIAction(title: "Website", image: UIImage(systemName: "globe")) { [weak self] _ in self?.act(.arrangeTabs(.website)) },
            ]))
        }
        if !keep.isEmpty { sections.append(UIMenu(options: .displayInline, children: keep)) }
        var close: [UIMenuElement] = []
        if !tab.isPinned {
            let rest = ordinary.filter { $0.id != tab.id }.map(\.id)
            if !rest.isEmpty {
                close.append(UIAction(title: "Close Other Tabs", image: UIImage(systemName: "xmark.square"),
                                      attributes: .destructive) { [weak self] _ in self?.act(.closeTabs(rest)) })
            }
            if ordinary.count > 1 {
                close.append(UIAction(title: "Close All \(ordinary.count) Tabs", image: UIImage(systemName: "xmark.square.fill"),
                                      attributes: .destructive) { [weak self] _ in
                    self?.act(.closeTabs(ordinary.map(\.id)))
                    // Nothing left to choose from: the bar, and the start page.
                    self?.done(nil)
                })
            }
        }
        // A pinned tab closes by going back to its address and letting its page go.
        close.append(UIAction(title: "Close Tab", image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in
            self?.act(.close(tab.id))
        })
        sections.append(UIMenu(options: .displayInline, children: close))
        return UIMenu(children: sections)
    }

    private func share(_ url: URL, from source: UIView) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = source
            popover.sourceRect = source.bounds
        }
        present(sheet, animated: true)
    }
}

// MARK: A tab's card

/// A tab in the overview: a picture of its page (or its site's icon, before
/// there is one), its name under it, and a close button on the picture; the
/// tab on screen ringed in the space's colour, the ring's corners following
/// the picture's. A swipe sideways throws it off and closes it.
@MainActor
final class TabCardCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    var closed: (() -> Void)?

    private let card = UIView()
    private let shadow = UIView()
    private let picture = UIView()
    private let image = UIImageView()
    private let placeholder = SiteIconUIView()
    private let ring = UIView()
    private let icon = SiteIconUIView()
    private let name = UILabel()
    private let close = WideButton(type: .system)
    private var aspect: CGFloat = 0
    private var ticked = false
    private let tick = UIImpactFeedbackGenerator(style: .medium)

    private static let radius: CGFloat = 18
    /// Between the picture and the ring around the tab on screen.
    private static let gap: CGFloat = 4
    private static let ratio: CGFloat = 0.78
    private static let label: CGFloat = 18

    /// How tall a card is for its width: the picture, the ring's room, the name.
    static func height(forWidth width: CGFloat) -> CGFloat {
        ((width - gap * 2) / ratio).rounded() + gap * 2 + 6 + label
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(card)
        ring.layer.borderWidth = 2.5
        ring.layer.cornerRadius = Self.radius + Self.gap
        ring.layer.cornerCurve = .continuous
        card.addSubview(ring)
        shadow.layer.shadowColor = UIColor.black.cgColor
        shadow.layer.shadowOffset = CGSize(width: 0, height: 3)
        shadow.layer.shadowRadius = 10
        card.addSubview(shadow)
        picture.clipsToBounds = true
        picture.layer.cornerRadius = Self.radius
        picture.layer.cornerCurve = .continuous
        picture.layer.borderWidth = 1
        picture.backgroundColor = Palette.UI.card
        shadow.addSubview(picture)
        placeholder.size = 36
        picture.addSubview(placeholder)
        image.contentMode = .scaleToFill
        picture.addSubview(image)
        icon.size = 16
        card.addSubview(icon)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.textColor = Palette.UI.ink
        card.addSubview(name)

        var style: UIButton.Configuration
        if #available(iOS 26.0, *) {
            style = .glass()
        } else {
            style = .gray()
        }
        style.cornerStyle = .capsule
        style.image = UIImage(systemName: "xmark")
        style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        style.baseForegroundColor = Palette.UI.ink
        style.contentInsets = .zero
        close.configuration = style
        close.addAction(UIAction { [weak self] _ in self?.closed?() }, for: .primaryActionTriggered)
        card.addSubview(close)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        pan.delegate = self
        contentView.addGestureRecognizer(pan)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Close Tab") { [weak self] _ in
            self?.closed?()
            return true
        }]
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: TabCardCell, _) in self.colours() }
        colours()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(tab: TabRecord, image found: UIImage?, current: Bool, color: UIColor) {
        image.image = found
        image.isHidden = found == nil
        aspect = found.map { $0.size.height / max($0.size.width, 1) } ?? 0
        placeholder.url = tab.url
        placeholder.isHidden = found != nil
        icon.url = tab.url
        name.text = tab.label
        name.font = .systemFont(ofSize: 13, weight: current ? .semibold : .medium)
        ring.layer.borderColor = color.cgColor
        ring.isHidden = !current
        close.accessibilityLabel = "Close \(tab.label)"
        accessibilityLabel = tab.label
        accessibilityTraits = current ? [.button, .selected] : .button
        setNeedsLayout()
    }

    private func colours() {
        let dark = traitCollection.userInterfaceStyle == .dark
        picture.layer.borderColor = UIColor(white: dark ? 1 : 0, alpha: 0.1).cgColor
        shadow.layer.shadowOpacity = dark ? 0.3 : 0.08
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = contentView.bounds
        let width = contentView.bounds.width
        let pictureWidth = width - Self.gap * 2
        let pictureHeight = (pictureWidth / Self.ratio).rounded()
        ring.frame = CGRect(x: 0, y: 0, width: width, height: pictureHeight + Self.gap * 2)
        shadow.frame = CGRect(x: Self.gap, y: Self.gap, width: pictureWidth, height: pictureHeight)
        shadow.layer.shadowPath = UIBezierPath(roundedRect: shadow.bounds, cornerRadius: Self.radius).cgPath
        picture.frame = shadow.bounds
        placeholder.frame = CGRect(x: pictureWidth / 2 - 18, y: pictureHeight / 2 - 18, width: 36, height: 36)
        // The top of the page, where what it is shows. A picture wider than
        // the card (a desktop page's) fills its height and shows its left
        // side: cut, never stretched.
        if aspect == 0 || pictureWidth * aspect >= pictureHeight {
            image.frame = CGRect(x: 0, y: 0, width: pictureWidth, height: max(pictureHeight, pictureWidth * aspect))
        } else {
            image.frame = CGRect(x: 0, y: 0, width: pictureHeight / aspect, height: pictureHeight)
        }
        close.frame = CGRect(x: width - Self.gap - 9 - 26, y: Self.gap + 9, width: 26, height: 26)
        let row = ring.frame.maxY + 6
        icon.frame = CGRect(x: Self.gap + 2, y: row + 1, width: 16, height: 16)
        name.frame = CGRect(x: icon.frame.maxX + 6, y: row, width: max(0, width - icon.frame.maxX - 6 - Self.gap), height: Self.label)
    }

    override var isHighlighted: Bool {
        didSet {
            guard card.transform.tx == 0 else { return }
            UIView.animate(springDuration: 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.card.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        card.transform = .identity
        card.alpha = 1
        ticked = false
    }

    /// The picture alone, in its corners, for the menu to lift.
    func preview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: picture.bounds, cornerRadius: Self.radius)
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: picture, parameters: parameters)
    }

    // MARK: Throwing it away

    /// Sideways and more sideways than up or down; up and down is the
    /// grid's scroll. UIKit asks a view this for its ancestors' gestures
    /// too, the grid's scroll among them: those it leaves alone.
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture.view === contentView, let pan = gesture as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gesture)
        }
        let velocity = pan.velocity(in: contentView)
        return abs(velocity.x) > abs(velocity.y) * 1.2
    }

    /// The grid's own scroll waits for this one to say it isn't a sideways swipe.
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other.view is UICollectionView && other is UIPanGestureRecognizer
    }

    @objc private func swiped(_ pan: UIPanGestureRecognizer) {
        let width = max(contentView.bounds.width, 1)
        let x = pan.translation(in: contentView).x
        let line = width * 0.45
        switch pan.state {
        case .began:
            ticked = false
            tick.prepare()
        case .changed:
            card.transform = CGAffineTransform(translationX: x, y: 0)
            card.alpha = 1 - min(abs(x) / (width * 1.4), 0.6)
            // A firm tap where letting go will close it, and again if it comes back.
            let past = abs(x) > line
            if past != ticked {
                ticked = past
                tick.impactOccurred(intensity: past ? 1 : 0.6)
            }
        case .ended, .cancelled, .failed:
            let speed = pan.velocity(in: contentView).x
            // Where a throw would come to rest, as Apple projects a scroll's.
            let projected = x + speed / 1000 * 0.998 / (1 - 0.998)
            let thrown = pan.state == .ended && (abs(projected) > width * 0.9 || abs(x) > line) && (x == 0 || projected * x > 0)
            if thrown {
                if !ticked { tick.impactOccurred(intensity: 1) }
                let away = (projected >= 0 ? 1 : -1) * (window?.bounds.width ?? width * 3)
                let velocity = abs(speed) / max(abs(away - x), 1)
                UIView.animate(springDuration: 0.35, bounce: 0, initialSpringVelocity: velocity,
                               options: [.beginFromCurrentState]) {
                    self.card.transform = CGAffineTransform(translationX: away, y: 0)
                    self.card.alpha = 0
                } completion: { _ in
                    self.closed?()
                }
            } else {
                UIView.animate(springDuration: 0.35, bounce: 0.2, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.card.transform = .identity
                    self.card.alpha = 1
                }
            }
            ticked = false
        default:
            break
        }
    }
}

/// A button whose touch reaches past what it draws, to 44 points.
final class WideButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = max(0, (44 - bounds.width) / 2)
        let dy = max(0, (44 - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }
}

// MARK: The dock

/// The pinned tabs as the iPhone's dock has its apps: icons on tiles, on a
/// pane of glass at the bottom, floating over the grid as it scrolls, the
/// icons scrolling sideways when there are more than fit, centred when
/// they all do. A dot under the tab on screen. A tap goes
/// to it; a long press has its menu.
@MainActor
final class PinnedDock: UIView {
    static let height: CGFloat = 92
    private static let tile: CGFloat = 60
    private static let spacing: CGFloat = 18
    private static let inset: CGFloat = 16

    var chosen: ((UUID) -> Void)?
    var menu: ((TabRecord, UIView) -> UIMenu?)?

    private let platter: UIVisualEffectView
    private let scroller = UIScrollView()
    private var icons: [DockIcon] = []
    private var current: UUID?

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            platter = UIVisualEffectView(effect: UIGlassEffect())
            platter.cornerConfiguration = .corners(radius: .fixed(32))
        } else {
            platter = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            platter.layer.cornerRadius = 32
            platter.layer.cornerCurve = .continuous
            platter.clipsToBounds = true
        }
        super.init(frame: frame)
        addSubview(platter)
        scroller.showsHorizontalScrollIndicator = false
        scroller.alwaysBounceHorizontal = false
        scroller.clipsToBounds = true
        platter.contentView.addSubview(scroller)
        accessibilityLabel = "Pinned tabs"
        shouldGroupAccessibilityChildren = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The pinned tabs as they are now, the one on screen marked.
    func show(_ tabs: [TabRecord], current: UUID?, color: UIColor) {
        while icons.count < tabs.count {
            let icon = DockIcon()
            icon.addAction(UIAction { [weak self, weak icon] _ in
                guard let id = icon?.tab?.id else { return }
                self?.chosen?(id)
            }, for: .primaryActionTriggered)
            scroller.addSubview(icon)
            icons.append(icon)
        }
        while icons.count > tabs.count {
            icons.removeLast().removeFromSuperview()
        }
        for (icon, tab) in zip(icons, tabs) {
            icon.configure(tab: tab, current: tab.id == current, color: color)
            icon.menu = menu?(tab, icon)
        }
        let moved = self.current != current
        self.current = current
        setNeedsLayout()
        if moved {
            layoutIfNeeded()
            if let shown = icons.first(where: { $0.tab?.id == current }) {
                scroller.scrollRectToVisible(shown.frame.insetBy(dx: -Self.inset, dy: 0), animated: false)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        platter.frame = bounds
        scroller.frame = platter.bounds
        let count = CGFloat(icons.count)
        let row = count * Self.tile + max(count - 1, 0) * Self.spacing + Self.inset * 2
        // Centred while they fit, as the dock's apps are; scrolling once they don't.
        let start = max((bounds.width - row) / 2, 0) + Self.inset
        for (index, icon) in icons.enumerated() {
            icon.frame = CGRect(x: start + CGFloat(index) * (Self.tile + Self.spacing), y: 12, width: Self.tile, height: Self.tile + 14)
        }
        scroller.contentSize = CGSize(width: max(row, bounds.width), height: bounds.height)
    }
}

/// One pinned tab in the dock: its site's icon on a tile with an app icon's
/// corners, and a dot under it while it is the tab on screen.
@MainActor
final class DockIcon: UIButton {
    private(set) var tab: TabRecord?
    private let tile = UIView()
    private let icon = SiteIconUIView()
    private let dot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        var plain = UIButton.Configuration.plain()
        plain.contentInsets = .zero
        configuration = plain
        tile.isUserInteractionEnabled = false
        tile.backgroundColor = Palette.UI.card
        tile.layer.cornerRadius = 60 * 0.225
        tile.layer.cornerCurve = .continuous
        tile.layer.borderWidth = 1
        addSubview(tile)
        icon.size = 34
        icon.isUserInteractionEnabled = false
        tile.addSubview(icon)
        dot.isUserInteractionEnabled = false
        dot.layer.cornerRadius = 2.5
        addSubview(dot)
        showsMenuAsPrimaryAction = false
        configurationUpdateHandler = { button in
            UIView.animate(springDuration: 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                button.transform = button.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: DockIcon, _) in self.colours() }
        colours()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(tab: TabRecord, current: Bool, color: UIColor) {
        self.tab = tab
        icon.url = tab.url ?? tab.pinned
        dot.backgroundColor = color
        dot.isHidden = !current
        accessibilityLabel = "\(tab.label), pinned"
        accessibilityTraits = current ? [.button, .selected] : .button
    }

    private func colours() {
        tile.layer.borderColor = UIColor(white: traitCollection.userInterfaceStyle == .dark ? 1 : 0, alpha: 0.08).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        icon.frame = CGRect(x: 13, y: 13, width: 34, height: 34)
        dot.frame = CGRect(x: 27.5, y: 66, width: 5, height: 5)
    }

    /// The tile alone lifts for the menu, in its corners, not the dot under it.
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: tile.bounds, cornerRadius: 60 * 0.225)
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: tile, parameters: parameters)
    }
}
