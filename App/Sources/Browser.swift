import Combine
import PadCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// What a window's bars show, kept up to date from its page.
@MainActor
final class WindowModel: ObservableObject {
    @Published var spaceID: UUID
    @Published var tabID: UUID?
    @Published var url: URL?
    @Published var title = ""
    @Published var loading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var secure = false
    @Published var signIn = false
    /// The address must show, whatever Settings says: a sign-in page, a page
    /// that failed, a new tab (AddressVisibility).
    @Published var addressRequired = false
    /// The address is in view: the address bar, in the separate layout; in
    /// the compact one, the tab on screen says where it is rather than what
    /// it is called.
    @Published var showsAddress = false
    @Published var editingAddress = false
    @Published var banner: Banner?
    /// The colour along the top of the page, which the bars take on.
    @Published var siteColor: SiteColor?
    /// The page is one of the space's bookmarks (the star in the address).
    @Published var bookmarked = false
    /// A phone-width window: the bars at the bottom, as on an iPhone (PhoneBar).
    @Published var phone = false
    /// The page on screen is its mobile site (SiteMode).
    @Published var mobileSite = false
    /// The page is in the iPhone's desktop view (DesktopPad), or could be.
    @Published var desktopView = false
    @Published var canDesktopView = false

    init(spaceID: UUID) {
        self.spaceID = spaceID
    }

    /// The page, or something on it, came over a connection anyone on the
    /// way can read. An http address says so at once; for the rest, WebKit
    /// knows only once the page has loaded, so a page still loading isn't
    /// marked, rather than marked and then unmarked a moment later.
    var insecure: Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "http" || (!loading && !secure)
    }
}

/// A line under the address bar that something needs saying.
enum Banner: Equatable {
    /// Google refused to sign in here (SignIn.googleRefused).
    case googleRefused
    /// The page's process kept ending (CrashGuard).
    case exhausted
    case failed(String)
}

/// One window: a row of tabs, an address bar when it is wanted, and a page.
///
/// The page gets everything it can: the window's whole width, the trackpad
/// (Pointer), the keys (PageView, Menus), the focus whenever the window
/// becomes active. The browser's own shortcuts are ⌃⌥ ones (Menus), out of
/// the way of any page's.
@MainActor
final class Browser: UIViewController, PageHost, UIAdaptivePresentationControllerDelegate, UIDocumentPickerDelegate,
    UIGestureRecognizerDelegate {
    let model: WindowModel
    /// The page on screen; with two side by side, the one with the keys,
    /// which the bars show and act on.
    private(set) var page: Page?
    /// The other pane, when the tab on screen is split with another tab.
    private(set) var partner: Page?
    private var firstTab: UUID?
    private var connected = true

    private let stack = UIStackView()
    private let stage = Stage()
    private let picture = UIImageView()
    private let partnerPicture = UIImageView()
    private let divider = SplitDivider()
    /// A line along the top of the pane with the keys, while there are two.
    private let focusEdge = UIView()
    /// Where the divider is while it is dragged, before the workspace hears.
    private var dragRatio: Double?
    private var topBar: UIHostingController<TopBar>?
    private var phoneBar: UIHostingController<PhoneBar>?
    /// The bars' bottom: the safe area's, or the keyboard's while an address
    /// is typed on a phone, so the bar at the bottom rides above it.
    /// The phone bar's height: shorter while an address is typed (PhoneBar.typingHeight).
    private var phoneHeight: NSLayoutConstraint?
    /// The cursor and the trackpad over a page in the iPhone's desktop view.
    private var desktopPad: DesktopPad?
    private weak var barSwipe: BarSwipe?
    /// The phone's tabs, while they show or the bar is turning into them.
    private var tabSheet: TabSheet?
    /// What the tabs were left for, done once they have gone: a new tab's
    /// typing waits for the bar to be back.
    private var afterTabs: BarAction?
    /// The stack's bottom: the safe area's on iPad; on a phone the screen's,
    /// so the page runs on under the bar and the home indicator.
    private var safeBottom: NSLayoutConstraint?
    private var screenBottom: NSLayoutConstraint?
    /// The phone bar's bottom: the safe area's, or the keyboard's while an
    /// address is typed.
    private var barSafeBottom: NSLayoutConstraint?
    private var barKeyboardBottom: NSLayoutConstraint?
    /// Behind the phone bar: the page through it, blurred more the lower it is (BarBackdrop).
    private let barBackdrop = BarBackdrop()
    private var addressBar: UIHostingController<AddressBar>?
    private var bannerBar: UIHostingController<BannerBar>?
    private var empty: UIHostingController<EmptySpace>?
    private var start: UIHostingController<StartPage>?
    private var diagnostics: UIHostingController<DiagnosticsView>?
    private var subscriptions: Set<AnyCancellable> = []

    var isConnected: Bool { connected }

    /// The tabs this window has on screen: one, or a split's two.
    var shownTabs: [UUID] {
        [model.tabID, partner?.tab].compactMap { $0 }
    }

    func shows(_ tab: UUID) -> Bool {
        model.tabID == tab || partner?.tab == tab
    }

    init(state: WindowState) {
        let workspace = Session.shared.workspace
        let space = state.space.flatMap { workspace.space($0) } ?? workspace.spaces[0]
        model = WindowModel(spaceID: space.id)
        firstTab = state.tab ?? space.selected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var state: WindowState {
        WindowState(space: model.spaceID, tab: model.tabID)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.UI.ground
        Session.shared.register(self)
        build()
        Session.shared.$workspace
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.workspaceChanged() }
            .store(in: &subscriptions)
        Session.shared.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshChrome() }
            .store(in: &subscriptions)
        // A window that turns phone-width (an iPhone, the Duo folding, a narrow
        // iPad window) moves its bars to the bottom, and back.
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.refreshChrome()
        }
        show(tab: firstTab, inSpace: model.spaceID, userInitiated: false)
    }

    /// The window is gone (its scene was closed): its page stays, off
    /// screen now, for the Freezer to decide about.
    func disconnect() {
        connected = false
        detach()
        Session.shared.unregister(self)
        Session.shared.pages.enforce()
    }

    // MARK: Layout

    private func build() {
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        let bottom = stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        safeBottom = bottom
        screenBottom = stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safe.topAnchor),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            bottom,
        ])

        let session = Session.shared
        let top = embed(TopBar(session: session, window: model) { [weak self] in self?.act($0) })
        top.view.heightAnchor.constraint(equalToConstant: Metrics.bar).isActive = true
        topBar = top

        let address = embed(AddressBar(session: session, window: model) { [weak self] in self?.act($0) })
        address.view.heightAnchor.constraint(equalToConstant: Metrics.bar).isActive = true
        addressBar = address

        let banner = embed(BannerBar(window: model) { [weak self] in self?.act($0) })
        banner.sizingOptions = .intrinsicContentSize
        bannerBar = banner

        stage.clipsToBounds = true
        stage.backgroundColor = Palette.UI.ground
        stage.laidOut = { [weak self] in self?.layoutPanes() }
        stack.addArrangedSubview(stage)

        // Over the page rather than under it, as Safari's: the page runs on
        // beneath, seen through the bar's blur.
        let phone = embed(PhoneBar(session: session, window: model) { [weak self] in self?.act($0) }, inStack: false)
        phone.view.translatesAutoresizingMaskIntoConstraints = false
        barBackdrop.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(barBackdrop, belowSubview: phone.view)
        let phoneHeight = phone.view.heightAnchor.constraint(equalToConstant: PhoneBar.height)
        let barBottom = phone.view.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        barSafeBottom = barBottom
        barKeyboardBottom = phone.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            phoneHeight, barBottom,
            phone.view.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            phone.view.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            // A little above the bar, so the page fades into the blur rather than meeting an edge.
            barBackdrop.topAnchor.constraint(equalTo: phone.view.topAnchor, constant: -24),
            barBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            barBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        self.phoneHeight = phoneHeight
        phoneBar = phone
        // A swipe up on the bar shows the tabs. UIKit's, on the bar's view:
        // SwiftUI's buttons keep a drag that starts on them to themselves.
        let swipe = BarSwipe(target: self, action: #selector(swipedBar(_:)))
        swipe.delegate = self
        phone.view.addGestureRecognizer(swipe)
        barSwipe = swipe
        // A touch on the page while an address is typed puts the typing
        // away, as in Safari; the touch itself stays the page's.
        let away = UITapGestureRecognizer(target: self, action: #selector(touchedPage))
        away.cancelsTouchesInView = false
        away.delaysTouchesBegan = false
        away.delaysTouchesEnded = false
        away.delegate = self
        stage.addGestureRecognizer(away)

        // A click in the pane beside gives it the keys, and the bars.
        let landing = TouchDown(target: nil, action: nil)
        landing.delegate = self
        landing.landed = { [weak self] point in self?.landed(at: point) }
        stage.addGestureRecognizer(landing)

        for frozen in [picture, partnerPicture] {
            frozen.contentMode = .scaleAspectFill
            frozen.clipsToBounds = true
            frozen.isUserInteractionEnabled = false
            frozen.isHidden = true
            frozen.frame = stage.bounds
            stage.addSubview(frozen)
        }

        let blank = UIHostingController(rootView: EmptySpace(session: session, window: model) { [weak self] in self?.act($0) })
        addChild(blank)
        blank.view.frame = stage.bounds
        blank.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blank.view.backgroundColor = .clear
        blank.view.isHidden = true
        stage.addSubview(blank.view)
        blank.didMove(toParent: self)
        empty = blank

        // A new tab's page: the space's bookmarks, until it goes somewhere.
        let start = UIHostingController(rootView: StartPage(session: session, window: model) { [weak self] in self?.act($0) })
        addChild(start)
        start.view.frame = stage.bounds
        start.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        start.view.backgroundColor = Palette.UI.ground
        start.view.isHidden = true
        stage.addSubview(start.view)
        start.didMove(toParent: self)
        self.start = start

        divider.moved = { [weak self] x in self?.dragDivider(to: x) }
        divider.ended = { [weak self] in self?.dropDivider() }
        divider.centered = { [weak self] in
            guard let tab = self?.model.tabID else { return }
            Session.shared.change { $0.setSplitRatio(tab, to: 0.5) }
        }
        stage.addSubview(divider)
        focusEdge.isUserInteractionEnabled = false
        focusEdge.isHidden = true
        stage.addSubview(focusEdge)

        refreshChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPanes()
    }

    private func embed<V: View>(_ root: V, inStack: Bool = true) -> UIHostingController<V> {
        let host = UIHostingController(rootView: root)
        // The stack already keeps the bars inside the safe area. Left to
        // SwiftUI, the keyboard's arrival moved what they draw up out of
        // sight, .ignoresSafeArea(.keyboard) or not: both bars went blank
        // whenever a field had the focus (iPadOS 27).
        host.safeAreaRegions = []
        // The window's own colour shows through: the site's (siteColor).
        host.view.backgroundColor = .clear
        addChild(host)
        if inStack { stack.addArrangedSubview(host.view) } else { view.addSubview(host.view) }
        host.didMove(toParent: self)
        return host
    }

    /// Which bars show, from Settings and the page. In the compact layout
    /// the address is in the tab on screen, so the row of tabs shows
    /// whenever an address must: on sign-in pages, while one is typed, when
    /// a page failed, on a new tab, even with the tab bar turned off.
    private func refreshChrome() {
        let session = Session.shared
        let preferences = session.preferences
        let compact = preferences.layout == .compact
        let url = page?.view.url ?? model.tabID.flatMap { session.workspace.tab($0)?.url }
        let signIn = page?.passwordField ?? false
        let failed = page?.failure != nil
        let required = AddressVisibility.shows(mode: .automatic, url: url, passwordField: signIn,
                                               editing: false, failed: failed)
        if model.addressRequired != required { model.addressRequired = required }
        let mustShow = required || model.editingAddress
        // Typing doesn't count in the compact layout: the field is drawn
        // over the tab, which keeps saying what it said, and its size.
        let showsAddress = AddressVisibility.shows(
            mode: preferences.address, url: url, passwordField: signIn, editing: !compact && model.editingAddress,
            failed: failed
        )
        if model.showsAddress != showsAddress { model.showsAddress = showsAddress }
        let phone = traitCollection.horizontalSizeClass == .compact
        if model.phone != phone { model.phone = phone }
        topBar?.view.isHidden = phone || !(preferences.tabBar || (compact && mustShow))
        addressBar?.view.isHidden = phone || compact || !model.showsAddress
        // On a phone the bar at the bottom is the only way around: always there.
        phoneBar?.view.isHidden = !phone
        // The tabs grow out of the phone's bar; with the bar gone, they go too.
        if !phone { tabSheet?.closeNow() }
        // The one going first, so the two are never on together.
        if phone, safeBottom?.isActive == true {
            safeBottom?.isActive = false
            screenBottom?.isActive = true
        } else if !phone, screenBottom?.isActive == true {
            screenBottom?.isActive = false
            safeBottom?.isActive = true
        }
        let typing = phone && model.editingAddress
        // Only the address rides over the keyboard, as in Safari; the page
        // takes the room the tools leave, at the speed the tools go.
        let height = typing ? PhoneBar.typingHeight : PhoneBar.height
        if let phoneHeight, phoneHeight.constant != height {
            phoneHeight.constant = height
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) { self.view.layoutIfNeeded() }
        }
        if typing, barSafeBottom?.isActive == true {
            barSafeBottom?.isActive = false
            barKeyboardBottom?.isActive = true
        } else if !typing, barKeyboardBottom?.isActive == true {
            barKeyboardBottom?.isActive = false
            barSafeBottom?.isActive = true
        }
        // The desktop view is the phone's, and never on a hands-off page,
        // where nothing may reach the page but the finger.
        if let page, page.desktopView, !phone || page.isHandsOff { leaveDesktopView() }
        let desktop = page?.desktopView ?? false
        if model.desktopView != desktop { model.desktopView = desktop }
        let canDesktop = phone && page?.view.url != nil && page?.isHandsOff == false
        if model.canDesktopView != canDesktop { model.canDesktopView = canDesktop }
        if desktop { showDesktopPad() } else if desktopPad != nil { hideDesktopPad() }
        bannerBar?.view.isHidden = model.banner == nil
        start?.view.isHidden = !(page != nil && model.url == nil)
        let bookmarked = url.flatMap { session.workspace.bookmark(for: $0, in: model.spaceID) } != nil
        if model.bookmarked != bookmarked { model.bookmarked = bookmarked }
        showDiagnostics(preferences.diagnostics)
        applySiteColor()
    }

    /// The bars and the strip under the status bar in the colour along the
    /// top of the page, so page and bars read as one, as in Safari. What
    /// they draw turns light on a dark colour and dark on a light one; a
    /// change of colour eases in rather than flashing.
    private func applySiteColor() {
        let color = model.siteColor
        let style: UIUserInterfaceStyle = color.map { $0.isDark ? .dark : .light } ?? .unspecified
        for bar in [topBar, addressBar, bannerBar, phoneBar] as [UIViewController?] where bar?.overrideUserInterfaceStyle != style {
            bar?.overrideUserInterfaceStyle = style
        }
        let ground = color?.uiColor ?? Palette.UI.ground
        if view.backgroundColor != ground {
            UIView.animate(withDuration: 0.25) { self.view.backgroundColor = ground }
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard let color = model.siteColor else { return .default }
        return color.isDark ? .lightContent : .darkContent
    }

    private func showDiagnostics(_ on: Bool) {
        if !on {
            diagnostics?.willMove(toParent: nil)
            diagnostics?.view.removeFromSuperview()
            diagnostics?.removeFromParent()
            diagnostics = nil
            return
        }
        guard diagnostics == nil else { return }
        let hud = UIHostingController(rootView: DiagnosticsView { [weak self] in self?.page })
        hud.view.backgroundColor = .clear
        hud.view.isUserInteractionEnabled = false
        hud.sizingOptions = .intrinsicContentSize
        addChild(hud)
        hud.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud.view)
        NSLayoutConstraint.activate([
            hud.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            hud.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        hud.didMove(toParent: self)
        diagnostics = hud
    }

    // MARK: Showing a tab

    /// Shows a tab in this window. One another window shows is brought
    /// forward there instead when you asked for it; a window coming back
    /// takes another tab of its space, or none.
    func show(tab id: UUID?, inSpace space: UUID, userInitiated: Bool = true) {
        let session = Session.shared
        guard let id, let record = session.workspace.tab(id), let owner = session.workspace.spaceID(of: id) else {
            showEmpty(space: session.workspace.space(space) == nil ? session.workspace.spaces[0].id : space)
            return
        }
        if let other = session.browser(showing: id), other !== self {
            if userInitiated {
                session.bringForward(other)
            } else if let free = session.workspace.space(owner)?.tabs.first(where: { session.browser(showing: $0.id) == nil }) {
                show(tab: free.id, inSpace: owner, userInitiated: false)
            } else {
                showEmpty(space: owner)
            }
            return
        }
        // Already here, and still live: a tab moved to another space has a
        // new page to load in that space's store.
        if model.tabID == id, let page, session.pages.live[id] === page {
            focusPage()
            return
        }
        let pairedWith = session.workspace.split(containing: id)?.partner(of: id)
        // The pane beside, still split with the tab on screen: it takes the keys.
        if let partner, partner.tab == id, session.pages.live[id] === partner, let page, pairedWith == page.tab {
            swapPanes()
            return
        }
        // The tab on screen split with the one asked for stays up, as the other pane.
        if let page, pairedWith == page.tab, session.pages.live[page.tab] === page {
            detachPartner()
            self.page = nil
            partner = page
            partnerPicture.image = picture.image
            partnerPicture.alpha = picture.alpha
            partnerPicture.isHidden = picture.isHidden
            picture.isHidden = true
            picture.image = nil
        } else {
            detach()
        }
        let made = session.pages.page(for: record, in: owner)
        attach(made.page, thawed: made.thawed)
        // Going to another tab ends typing an address, as in Safari.
        model.editingAddress = false
        model.spaceID = owner
        model.tabID = id
        session.change { $0.select(id) }
        syncSplit()
        pageDidChange(made.page)
        focusPage()
        session.pages.enforce()
    }

    /// The other pane takes the keys: the bars show its page from now on.
    private func swapPanes() {
        guard let partner, let page else { return }
        self.page = partner
        self.partner = page
        let frozen = (picture.image, picture.alpha, picture.isHidden)
        picture.image = partnerPicture.image
        picture.alpha = partnerPicture.alpha
        picture.isHidden = partnerPicture.isHidden
        (partnerPicture.image, partnerPicture.alpha, partnerPicture.isHidden) = frozen
        model.editingAddress = false
        model.tabID = partner.tab
        Session.shared.change { $0.select(partner.tab) }
        layoutPanes()
        pageDidChange(partner)
        focusPage()
    }

    /// A touch or a click landed on the stage: in the pane beside, that pane
    /// gets the keys. The touch itself goes on to the page.
    private func landed(at point: CGPoint) {
        guard let partner, !partner.view.isHidden, partner.view.frame.contains(point) else { return }
        show(tab: partner.tab, inSpace: model.spaceID)
    }

    /// The tab split with the one on screen, up in its pane beside it; or
    /// taken down, when their split has ended or another window shows that
    /// tab.
    func syncSplit() {
        let session = Session.shared
        let workspace = session.workspace
        guard connected, let tab = model.tabID, page != nil, let other = workspace.split(containing: tab)?.partner(of: tab),
              let record = workspace.tab(other), let space = workspace.spaceID(of: other),
              !session.allBrowsers.contains(where: { $0 !== self && $0.isConnected && $0.shows(other) })
        else {
            if partner != nil {
                detachPartner()
                session.pages.enforce()
            }
            layoutPanes()
            return
        }
        if partner?.tab != other || session.pages.live[other] !== partner {
            detachPartner()
            let made = session.pages.page(for: record, in: space)
            made.page.host = self
            stage.insertSubview(made.page.view, at: 0)
            partner = made.page
            if made.thawed, let image = session.pages.picture(for: other) {
                partnerPicture.image = image
                partnerPicture.alpha = 1
                partnerPicture.isHidden = false
            }
            session.pages.enforce()
        }
        layoutPanes()
    }

    private func detachPartner() {
        guard let partner else { return }
        if partner.view.superview === stage { partner.view.removeFromSuperview() }
        if partner.host === self { partner.host = nil }
        self.partner = nil
        partnerPicture.isHidden = true
        partnerPicture.image = nil
    }

    /// The narrowest a window shows a split in: two pages each wide enough
    /// to read. Narrower, only the pane with the keys shows, and a click on
    /// the other half of the split's tab goes over to the other.
    private static let splitWidth: CGFloat = 2 * 360 + SplitDivider.width

    /// The tab on screen across the stage; or a split's two side by side,
    /// the divider between them and a line in the space's colour along the
    /// top of the one with the keys.
    private func layoutPanes() {
        let bounds = stage.bounds
        var main = bounds
        let split = model.tabID.flatMap { Session.shared.workspace.split(containing: $0) }
        if let page, let partner, let split, split.contains(partner.tab), bounds.width >= Self.splitWidth {
            let gap = SplitDivider.width
            let ratio = CGFloat(dragRatio ?? split.ratio)
            let leftWidth = ((bounds.width - gap) * ratio).rounded()
            let left = CGRect(x: 0, y: 0, width: leftWidth, height: bounds.height)
            let right = CGRect(x: leftWidth + gap, y: 0, width: bounds.width - leftWidth - gap, height: bounds.height)
            let onLeft = split.left == page.tab
            main = onLeft ? left : right
            partner.view.frame = onLeft ? right : left
            partner.view.isHidden = false
            partnerPicture.frame = partner.view.frame
            partnerPicture.isHidden = partnerPicture.image == nil
            divider.frame = CGRect(x: leftWidth, y: 0, width: gap, height: bounds.height)
            divider.isHidden = false
            focusEdge.frame = CGRect(x: main.minX, y: 0, width: main.width, height: 2)
            focusEdge.backgroundColor = Session.shared.workspace.space(model.spaceID)?.color.uiColor ?? .tintColor
            focusEdge.isHidden = false
        } else {
            partner?.view.isHidden = true
            partnerPicture.isHidden = true
            divider.isHidden = true
            focusEdge.isHidden = true
        }
        // Under the phone bar and the home indicator: the page goes on
        // there, told it is covered so its end scrolls clear of the bar and
        // its own bottom bars sit above it. The start page and the desktop
        // view stop at the bar.
        let covered = phoneCovered
        var clear = main
        clear.size.height = max(0, main.height - covered)
        if let page, let pad = desktopPad, pad.page === page {
            pad.layout(in: clear)
            page.obscure(bottom: 0)
        } else {
            page?.view.transform = .identity
            page?.view.frame = main
            page?.obscure(bottom: covered)
        }
        picture.frame = main
        start?.view.frame = clear
        barBackdrop.isHidden = !model.phone
    }

    /// How much of the stage's bottom the phone bar covers, with the home
    /// indicator under it: always the bar's resting height, so typing an
    /// address doesn't move the page.
    private var phoneCovered: CGFloat {
        guard model.phone, phoneBar?.view.isHidden == false else { return 0 }
        return view.safeAreaInsets.bottom + PhoneBar.height
    }


    private func dragDivider(to x: CGFloat) {
        let width = stage.bounds.width - SplitDivider.width
        guard width > 0 else { return }
        let ratio = Double((x - SplitDivider.width / 2) / width)
        dragRatio = min(max(ratio, Split.ratios.lowerBound), Split.ratios.upperBound)
        layoutPanes()
    }

    private func dropDivider() {
        guard let ratio = dragRatio, let tab = model.tabID else { return }
        Session.shared.change { $0.setSplitRatio(tab, to: ratio) }
        dragRatio = nil
        layoutPanes()
    }

    func showSpace(_ space: UUID) {
        let session = Session.shared
        guard let target = session.workspace.space(space) else { return }
        // A tab this window has beside the one on screen is free for it.
        let free = { (tab: UUID) -> Bool in
            let shower = session.browser(showing: tab)
            return shower == nil || shower === self
        }
        let choice = [target.selected].compactMap { $0 }.first(where: free) ?? target.tabs.first { free($0.id) }?.id
        if let choice {
            show(tab: choice, inSpace: space, userInitiated: false)
        } else {
            showEmpty(space: space)
        }
    }

    private func showEmpty(space: UUID) {
        detach()
        model.spaceID = space
        model.tabID = nil
        model.url = nil
        model.title = ""
        model.banner = nil
        model.loading = false
        model.siteColor = nil
        empty?.view.isHidden = false
        refreshChrome()
        updateSceneTitle()
    }

    private func attach(_ page: Page, thawed: Bool) {
        page.host = self
        page.view.frame = stage.bounds
        page.view.autoresizingMask = []
        page.view.isHidden = false
        stage.insertSubview(page.view, at: 0)
        empty?.view.isHidden = true
        self.page = page
        if thawed, let image = Session.shared.pages.picture(for: page.tab) {
            picture.image = image
            picture.alpha = 1
            picture.isHidden = false
        }
    }

    private func detach() {
        detachPartner()
        guard let page else { return }
        // While it still shows: the tab overview's picture of it.
        if model.phone { Session.shared.pages.keepPreview(of: page) }
        if page.view.superview === stage { page.view.removeFromSuperview() }
        if page.host === self { page.host = nil }
        self.page = nil
        picture.isHidden = true
        picture.image = nil
    }

    /// The picture of a frozen tab, taken away once its page has loaded.
    private func fadePicture() {
        guard !picture.isHidden, let page, !page.view.isLoading else { return }
        UIView.animate(withDuration: 0.2, animations: { self.picture.alpha = 0 }) { _ in
            self.picture.isHidden = true
            self.picture.image = nil
        }
    }

    private func workspaceChanged() {
        defer { refreshChrome() }
        let workspace = Session.shared.workspace
        if workspace.space(model.spaceID) == nil {
            showSpace(workspace.spaces[0].id)
            return
        }
        if let tab = model.tabID {
            if workspace.tab(tab) == nil {
                showSpace(model.spaceID)
                return
            }
            if let owner = workspace.spaceID(of: tab), owner != model.spaceID { model.spaceID = owner }
        }
        syncSplit()
        updateSceneTitle()
    }

    private func updateSceneTitle() {
        let space = Session.shared.workspace.space(model.spaceID)?.name ?? ""
        let title = model.title.isEmpty ? space : "\(model.title) · \(space)"
        view.window?.windowScene?.title = title
    }

    /// The keys back to the page: whenever the window becomes active, and
    /// after anything that took them (the palette, the address bar, a sheet).
    func focusPage() {
        guard let page, presentedViewController == nil, tabSheet == nil, !model.editingAddress else { return }
        _ = page.view.becomeFirstResponder()
    }

    // MARK: PageHost

    func pageDidChange(_ page: Page) {
        if page === partner, !partnerPicture.isHidden, !page.view.isLoading {
            UIView.animate(withDuration: 0.2, animations: { self.partnerPicture.alpha = 0 }) { _ in
                self.partnerPicture.isHidden = true
                self.partnerPicture.image = nil
            }
        }
        guard page === self.page else { return }
        let view = page.view
        model.url = view.url ?? Session.shared.workspace.tab(page.tab)?.url
        model.title = view.title ?? ""
        model.loading = view.isLoading
        model.progress = view.estimatedProgress
        model.canGoBack = view.canGoBack
        model.canGoForward = view.canGoForward
        model.secure = view.hasOnlySecureContent
        model.signIn = page.isSignIn
        model.siteColor = page.siteColor
        model.mobileSite = page.mode == .mobile
        if page.googleRefused {
            model.banner = .googleRefused
        } else if page.exhausted {
            model.banner = .exhausted
        } else {
            model.banner = page.failure.map(Banner.failed)
        }
        refreshChrome()
        updateSceneTitle()
        fadePicture()
    }

    func isShowing(_ page: Page) -> Bool {
        connected && (page === self.page || page === partner)
    }

    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView? {
        // A window with a size asked for is a pop-up: a sign-in, a share
        // dialog. It opens over this window and closes by itself when done.
        if features.width != nil || features.height != nil {
            let popup = Popup(opener: page, configuration: configuration)
            popup.closed = { [weak self] in self?.focusPage() }
            present(popup, animated: true)
            return popup.page.view
        }
        // Anything else is a tab, right after the one it came from.
        let session = Session.shared
        guard let id = session.change({ $0.openTab(action.request.url, in: page.space, after: page.tab) }) else { return nil }
        let child = session.pages.adopt(tab: id, space: page.space, configuration: configuration)
        detach()
        attach(child, thawed: false)
        model.tabID = id
        model.spaceID = page.space
        syncSplit()
        pageDidChange(child)
        focusPage()
        session.pages.enforce()
        return child.view
    }

    func pageDidClose(_ page: Page) {
        guard page === self.page || page === partner else { return }
        Session.shared.closeTab(page.tab)
    }

    var presenter: UIViewController? {
        var top: UIViewController = self
        while let next = top.presentedViewController { top = next }
        return top
    }

    // MARK: Commands

    override var keyCommands: [UIKeyCommand]? {
        if tabSheet != nil {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeTabsKey))
            escape.wantsPriorityOverSystemBehavior = true
            return (super.keyCommands ?? []) + [escape]
        }
        guard model.editingAddress else { return super.keyCommands }
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelAddress))
        escape.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [escape]
    }

    @objc func browserCommand(_ sender: UICommand) {
        guard let raw = sender.propertyList as? String, let command = Command(rawValue: raw) else { return }
        perform(command)
    }

    @objc func browserTab(_ sender: UICommand) {
        guard let number = sender.propertyList as? Int else { return }
        selectTab(number: number)
    }

    @objc private func cancelAddress() {
        act(.cancelAddress)
    }

    @objc private func closeTabsKey() {
        closeTabs(then: nil)
    }

    @objc private func touchedPage() {
        if model.editingAddress { act(.cancelAddress) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let swipe = barSwipe, gestureRecognizer === swipe else { return true }
        // Upward and more up than across; never while an address is typed,
        // where drags are the text field's.
        let velocity = swipe.velocity(in: swipe.view)
        return !model.editingAddress && velocity.y < 0 && abs(velocity.y) > abs(velocity.x)
    }

    /// A swipe up on the bar draws the tabs up out of it, under the finger
    /// (TabSheet). Measured against the window's view: the bar moves with
    /// the finger, so against the bar a drag would seem to go nowhere.
    @objc private func swipedBar(_ swipe: UIPanGestureRecognizer) {
        switch swipe.state {
        case .began:
            guard presentedViewController == nil, let sheet = makeTabSheet() else { return }
            sheet.beginDrag()
        case .changed:
            tabSheet?.drag(up: -swipe.translation(in: view).y)
        case .ended:
            tabSheet?.release(up: -swipe.velocity(in: view).y)
        case .cancelled, .failed:
            tabSheet?.release(up: 0)
        default:
            break
        }
    }

    func perform(_ command: Command) {
        let session = Session.shared
        switch command {
        case .palette: openPalette()
        case .newTab: newTab()
        case .closeTab:
            if let tab = model.tabID { session.closeTab(tab) }
        case .reopenTab:
            if let tab = session.change({ $0.reopen() }) { show(tab: tab, inSpace: model.spaceID) }
        case .address: act(.editAddress)
        case .reload: page?.reload()
        case .stop: page?.view.stopLoading()
        case .back: page?.view.goBack()
        case .forward: page?.view.goForward()
        case .nextTab: stepTab(1)
        case .previousTab: stepTab(-1)
        case .nextSpace: stepSpace(1)
        case .previousSpace: stepSpace(-1)
        case .newSpace: newSpace()
        case .newWindow:
            let tab = session.change { $0.openTab(nil, in: model.spaceID) }
            session.openWindow(space: model.spaceID, tab: tab)
        case .closeWindow:
            if let scene = view.window?.windowScene {
                UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
            }
        case .tabBar: session.preferences.tabBar.toggle()
        case .diagnostics: session.preferences.diagnostics.toggle()
        case .settings: openSettings()
        case .focusPage:
            model.editingAddress = false
            refreshChrome()
            focusPage()
        case .pinTab:
            guard let tab = model.tabID, let record = session.workspace.tab(tab) else { return }
            session.change { record.isPinned ? $0.unpin(tab) : $0.pin(tab) }
        case .splitTab:
            guard let tab = model.tabID else { return }
            if session.workspace.split(containing: tab) != nil {
                session.change { $0.separate(tab) }
            } else {
                splitWithNewTab()
            }
        case .bookmark: toggleBookmark()
        case .share: sharePage()
        case .siteMode: switchSiteMode()
        case .spaceSettings: openSpaceSettings(model.spaceID)
        case .importBookmarks: chooseBookmarksFile()
        }
    }

    /// A new tab beside the one on screen, typed into, as Dia's split.
    private func splitWithNewTab() {
        guard let tab = model.tabID, let new = Session.shared.change({ $0.splitWithNewTab(tab) }) else { return }
        show(tab: new, inSpace: model.spaceID)
        act(.editAddress)
    }

    /// `other` beside the tab on screen, on its right.
    private func split(with other: UUID) {
        let session = Session.shared
        guard let tab = model.tabID, session.change({ $0.split(tab, with: other) }) else { return }
        syncSplit()
        focusPage()
    }

    private func newTab() {
        guard let tab = Session.shared.change({ $0.openTab(nil, in: model.spaceID, after: model.tabID) }) else { return }
        show(tab: tab, inSpace: model.spaceID)
        act(.editAddress)
    }

    /// The next tab along that no other window shows, going round.
    private func stepTab(_ direction: Int) {
        let session = Session.shared
        guard let current = model.tabID, let tabs = session.workspace.space(model.spaceID)?.tabs, tabs.count > 1 else { return }
        for offset in 1..<tabs.count {
            guard let next = session.workspace.neighbour(of: current, by: direction * offset) else { return }
            // The pane beside is a step like any tab: it takes the keys.
            let shower = session.browser(showing: next)
            if shower == nil || shower === self {
                show(tab: next, inSpace: model.spaceID)
                return
            }
        }
    }

    private func stepSpace(_ direction: Int) {
        guard let next = Session.shared.workspace.spaceNeighbour(of: model.spaceID, by: direction),
              next != model.spaceID else { return }
        showSpace(next)
    }

    /// ⌃⌥1 to ⌃⌥8 the tab in that place, ⌃⌥9 the last.
    private func selectTab(number: Int) {
        guard let tabs = Session.shared.workspace.space(model.spaceID)?.tabs, !tabs.isEmpty else { return }
        let index = number >= 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        show(tab: tabs[index].id, inSpace: model.spaceID)
    }

    private func newSpace() {
        let number = Session.shared.workspace.spaces.count + 1
        Dialogs.name(title: "New Space", message: "A space has its own tabs and its own sign-ins.",
                     placeholder: "Space \(number)", initial: "", on: presenter ?? self) { [weak self] name in
            guard let self, let name else { return }
            let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let space = Session.shared.change { $0.addSpace(named: chosen.isEmpty ? "Space \(number)" : chosen) }
            self.showSpace(space)
            self.act(.editAddress)
        }
    }

    private func removeSpace(_ id: UUID) {
        guard let space = Session.shared.workspace.space(id), Session.shared.workspace.spaces.count > 1 else { return }
        Dialogs.confirmRemoval(of: space.name, tabs: space.tabs.count, on: presenter ?? self) { sure in
            if sure { Session.shared.removeSpace(id) }
        }
    }

    /// Everything the bars, the palette and the empty space can ask for.
    func act(_ action: BarAction) {
        let session = Session.shared
        switch action {
        case .select(let tab): show(tab: tab, inSpace: session.workspace.spaceID(of: tab) ?? model.spaceID)
        case .close(let tab): session.closeTab(tab)
        case .command(let command): perform(command)
        case .switchSpace(let space): showSpace(space)
        case .spaceInNewWindow(let space): session.openWindow(space: space, tab: nil)
        case .spaceSettings(let space): openSpaceSettings(space)
        case .removeSpace(let space): removeSpace(space)
        case .moveTab(let tab, let space): session.moveTab(tab, to: space)
        case .tabInNewWindow(let tab):
            // A tab goes to a window of its own alone; the pane beside it stays here.
            let beside = session.workspace.split(containing: tab)?.partner(of: tab)
            session.change { $0.separate(tab) }
            if model.tabID == tab {
                let next = beside ?? session.workspace.neighbour(of: tab, by: 1)
                let shower = next.flatMap { session.browser(showing: $0) }
                if let next, next != tab, shower == nil || shower === self {
                    show(tab: next, inSpace: model.spaceID)
                } else {
                    showEmpty(space: model.spaceID)
                }
            }
            session.openWindow(space: session.workspace.spaceID(of: tab), tab: tab)
        case .editAddress:
            model.editingAddress = true
            refreshChrome()
        case .cancelAddress:
            model.editingAddress = false
            refreshChrome()
            focusPage()
        case .go(let text):
            model.editingAddress = false
            go(text)
        case .open(let url):
            open(url)
        case .back: page?.view.goBack()
        case .forward: page?.view.goForward()
        case .reload: page?.reload()
        case .stop: page?.view.stopLoading()
        case .dismissBanner:
            model.banner = nil
            refreshChrome()
        case .pin(let tab): session.change { _ = $0.pin(tab) }
        case .unpin(let tab): session.change { _ = $0.unpin(tab) }
        case .backToPinned(let tab): backToPinned(tab)
        case .openInNewTab(let url):
            guard let tab = session.change({ $0.openTab(url, in: model.spaceID, after: model.tabID) }) else { return }
            show(tab: tab, inSpace: model.spaceID)
        case .toggleBookmark: toggleBookmark()
        case .removeBookmark(let id): session.change { $0.removeBookmark(id, in: model.spaceID) }
        case .importBookmarks: chooseBookmarksFile()
        case .showTabs: showTabs()
        case .desktopView: toggleDesktopView()
        case .splitWith(let other): split(with: other)
        case .splitWithNewTab: splitWithNewTab()
        case .separate(let tab): session.change { $0.separate(tab) }
        case .swapSides(let tab): session.change { $0.swapSides(tab) }
        }
    }

    // MARK: Pinned tabs and bookmarks

    /// A pinned tab at the page it was pinned with: loaded there when it is
    /// live, its frozen picture of where it had gone let go when it isn't.
    private func backToPinned(_ tab: UUID) {
        let session = Session.shared
        guard let url = session.change({ $0.backToPinned(tab) }) else { return }
        if let live = session.pages.live[tab] {
            live.load(url)
        } else {
            session.pages.close(tab)
        }
    }

    /// The page on screen as its desktop site, or its mobile one: kept for
    /// the site, and loaded again. A choice the window's size would make
    /// anyway isn't kept.
    private func switchSiteMode() {
        guard let page, let url = page.view.url, let key = SiteMode.siteKey(url.host) else { return }
        let wanted: SiteMode = page.mode == .desktop ? .mobile : .desktop
        let size = view.window?.bounds.size ?? view.bounds.size
        let natural = SiteMode.choose(host: nil, width: Double(size.width), height: Double(size.height), overrides: [:])
        Session.shared.preferences.siteModes[key] = wanted == natural ? nil : wanted
        page.reload(as: wanted)
    }

    // MARK: The iPhone's desktop view

    /// In: the page laid out at an iPad's size as its desktop site, the
    /// cursor over it (DesktopPad). Out: the page as the window's size has it.
    private func toggleDesktopView() {
        guard let page else { return }
        if page.desktopView {
            leaveDesktopView()
            return
        }
        guard model.phone, page.view.url != nil, !page.isHandsOff else { return }
        page.desktopView = true
        if page.mode != .desktop { page.reload(as: .desktop) }
        showDesktopPad()
        refreshChrome()
    }

    private func leaveDesktopView() {
        guard let page, page.desktopView else { return }
        page.desktopView = false
        hideDesktopPad()
        let size = view.window?.bounds.size ?? view.bounds.size
        let natural = SiteMode.choose(host: page.view.url?.host, width: Double(size.width), height: Double(size.height),
                                      overrides: Session.shared.preferences.siteModes)
        if natural != page.mode { page.reload(as: natural) }
        refreshChrome()
    }

    /// The pad for the page on screen when it is in the desktop view; none otherwise.
    private func showDesktopPad() {
        guard let page, page.desktopView else { return hideDesktopPad() }
        if desktopPad?.page === page { return }
        hideDesktopPad()
        let pad = DesktopPad(page: page, size: stage.bounds.size)
        stage.addSubview(pad)
        desktopPad = pad
        layoutPanes()
    }

    private func hideDesktopPad() {
        guard let pad = desktopPad else { return }
        desktopPad = nil
        pad.leave()
        layoutPanes()
    }

    /// Shows the space's tabs as a grid, from the phone bar's Tabs button:
    /// the bar turns into them, as a swipe up on it does.
    private func showTabs() {
        guard presentedViewController == nil else { return }
        makeTabSheet()?.open()
    }

    /// The sheet of tabs over the page, under the bar it grows out of; the
    /// one there already when the bar is caught on its way.
    private func makeTabSheet() -> TabSheet? {
        if let tabSheet { return tabSheet }
        guard model.phone, let bar = phoneBar?.view, !bar.isHidden else { return nil }
        let overview = UIHostingController(rootView: TabOverview(session: Session.shared, window: model, act: { [weak self] action in
            self?.act(action)
        }, done: { [weak self] action in
            self?.closeTabs(then: action)
        }))
        // The sheet sets where it ends; left to SwiftUI, the safe area changing
        // as the sheet moves would lay the tabs out again every frame.
        overview.safeAreaRegions = []
        let sheet = TabSheet(content: overview, bar: bar)
        sheet.closed = { [weak self] in self?.tabSheetClosed() }
        addChild(sheet)
        sheet.view.frame = view.bounds
        sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(sheet.view, belowSubview: bar)
        sheet.didMove(toParent: self)
        tabSheet = sheet
        return sheet
    }

    /// Done with the tabs. A tab goes on screen as the sheet goes, so the
    /// bar sinks back onto it; anything else waits until the bar is back.
    private func closeTabs(then action: BarAction?) {
        if let action, case .select = action { act(action) } else { afterTabs = action }
        tabSheet?.close()
    }

    private func tabSheetClosed() {
        guard let sheet = tabSheet else { return }
        sheet.willMove(toParent: nil)
        sheet.view.removeFromSuperview()
        sheet.removeFromParent()
        tabSheet = nil
        if let bar = phoneBar?.view {
            bar.transform = .identity
            bar.alpha = 1
            bar.isUserInteractionEnabled = true
        }
        if let action = afterTabs {
            afterTabs = nil
            act(action)
        } else {
            focusPage()
        }
    }

    /// The page on screen, through the system's share sheet. The web view
    /// goes in with its address: for a browser with Apple's entitlement, that
    /// is what puts Add to Home Screen in the sheet, so a web app gets its
    /// own icon on the Home Screen.
    private func sharePage() {
        guard let page, let url = page.view.url, presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: [url, page.view], applicationActivities: nil)
        // From the bar the address is in: the address bar, or the row of tabs.
        if let popover = sheet.popoverPresentationController,
           let anchor = [phoneBar?.view, addressBar?.view, topBar?.view, view].compactMap({ $0 }).first(where: { !$0.isHidden }) {
            popover.sourceView = anchor
            // Under a bar at the top; over the one at the bottom on a phone-width window.
            let below = anchor !== phoneBar?.view
            popover.sourceRect = CGRect(x: anchor.bounds.midX, y: below ? anchor.bounds.maxY - 6 : anchor.bounds.minY + 6,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = below ? .up : .down
        }
        sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.focusPage() }
        present(sheet, animated: true)
    }

    /// The page on screen into the space's bookmarks, or out of them.
    private func toggleBookmark() {
        guard let page, let url = page.view.url else { return }
        let session = Session.shared
        let space = model.spaceID
        if let known = session.workspace.bookmark(for: url, in: space) {
            session.change { $0.removeBookmark(known.id, in: space) }
        } else {
            session.change { $0.addBookmark(url, title: page.view.title ?? "", in: space) }
        }
        refreshChrome()
    }

    /// A bookmarks file for this window's space, from Files: Chrome's or
    /// Firefox's export, Safari's Bookmarks.html, or the ZIP Safari's
    /// Export Browsing Data saves to Downloads.
    func chooseBookmarksFile() {
        guard presentedViewController == nil else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.html, .zip], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let file = urls.first else { return }
        let outcome = Session.shared.importBookmarks(from: file, into: model.spaceID)
        try? FileManager.default.removeItem(at: file)
        let alert = UIAlertController(title: outcome.title, message: outcome.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.focusPage() })
        present(alert, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        focusPage()
    }

    func openSpaceSettings(_ space: UUID) {
        guard presentedViewController == nil else { return }
        let editor = UIHostingController(rootView: NavigationStack {
            SpaceEditor(session: Session.shared, spaceID: space) { [weak self] in
                self?.dismiss(animated: true) { self?.focusPage() }
            }
        })
        editor.modalPresentationStyle = .formSheet
        editor.presentationController?.delegate = self
        present(editor, animated: true)
    }

    /// A typed line: an address, or a search with the chosen engine.
    private func go(_ text: String) {
        guard let url = Destination.url(for: text, engine: Session.shared.preferences.engine) else {
            refreshChrome()
            focusPage()
            return
        }
        open(url)
    }

    /// A link from another app, or from any app once Safience is the default
    /// browser: a tab of its own after this one, so the page it lands on top
    /// of (a Figma file, a message half written) stays as it was.
    func openLink(_ url: URL) {
        guard let tab = Session.shared.change({ $0.openTab(url, in: model.spaceID, after: model.tabID) }) else { return }
        show(tab: tab, inSpace: model.spaceID)
    }

    /// An address, in this window's tab, or in a new tab when there is none.
    func open(_ url: URL) {
        if let page {
            page.load(url)
        } else if let tab = Session.shared.change({ $0.openTab(url, in: model.spaceID) }) {
            show(tab: tab, inSpace: model.spaceID)
        }
        model.editingAddress = false
        refreshChrome()
        focusPage()
    }

    // MARK: Palette and Settings

    func openPalette() {
        guard presentedViewController == nil else { return }
        let palette = PaletteController(window: model) { [weak self] entry in
            self?.dismiss(animated: true) { self?.choose(entry) }
        } cancel: { [weak self] in
            self?.dismiss(animated: true) { self?.focusPage() }
        }
        present(palette, animated: true)
    }

    private func choose(_ entry: PaletteEntry?) {
        guard let entry else {
            focusPage()
            return
        }
        switch entry.kind {
        case .tab(let tab, let space): show(tab: tab, inSpace: space)
        case .space(let space): showSpace(space)
        case .command(let command): perform(command)
        case .open(let url), .search(let url): open(url)
        }
        focusPage()
    }

    func openSettings() {
        guard presentedViewController == nil else { return }
        let settings = UIHostingController(rootView: SettingsView(session: Session.shared, spaceID: model.spaceID) { [weak self] in
            self?.dismiss(animated: true) { self?.focusPage() }
        })
        settings.modalPresentationStyle = .formSheet
        settings.presentationController?.delegate = self
        present(settings, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        focusPage()
    }
}

/// The phone bar's swipe up. SwiftUI's buttons would otherwise prevent it
/// whenever it starts on one of them, which on the bar is nearly always.
private final class BarSwipe: UIPanGestureRecognizer {
    override func canBePrevented(by preventing: UIGestureRecognizer) -> Bool {
        false
    }

    override func shouldRequireFailure(of other: UIGestureRecognizer) -> Bool {
        false
    }
}

/// Where the pages are. It lays them out itself when its size changes: the
/// window's own layout comes before the stack has given it its new size,
/// and a page sized then kept the height it had over the keyboard.
private final class Stage: UIView {
    var laidOut: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        laidOut?()
    }
}
