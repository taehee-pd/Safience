import Combine
import PadCore
import SwiftUI
import UIKit
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
    @Published var showsAddress = false
    @Published var editingAddress = false
    @Published var banner: Banner?

    init(spaceID: UUID) {
        self.spaceID = spaceID
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
final class Browser: UIViewController, PageHost, UIAdaptivePresentationControllerDelegate {
    let model: WindowModel
    private(set) var page: Page?
    private var firstTab: UUID?
    private var connected = true

    private let stack = UIStackView()
    private let stage = UIView()
    private let picture = UIImageView()
    private var topBar: UIHostingController<TopBar>?
    private var addressBar: UIHostingController<AddressBar>?
    private var bannerBar: UIHostingController<BannerBar>?
    private var empty: UIHostingController<EmptySpace>?
    private var diagnostics: UIHostingController<DiagnosticsView>?
    private var subscriptions: Set<AnyCancellable> = []

    var isConnected: Bool { connected }

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
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safe.topAnchor),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
        ])

        let session = Session.shared
        let top = embed(TopBar(session: session, window: model) { [weak self] in self?.act($0) })
        top.view.heightAnchor.constraint(equalToConstant: Metrics.bar).isActive = true
        topBar = top

        let address = embed(AddressBar(window: model) { [weak self] in self?.act($0) })
        address.view.heightAnchor.constraint(equalToConstant: Metrics.bar).isActive = true
        addressBar = address

        let banner = embed(BannerBar(window: model) { [weak self] in self?.act($0) })
        banner.sizingOptions = .intrinsicContentSize
        bannerBar = banner

        stage.clipsToBounds = true
        stage.backgroundColor = Palette.UI.ground
        stack.addArrangedSubview(stage)

        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.isUserInteractionEnabled = false
        picture.isHidden = true
        picture.frame = stage.bounds
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stage.addSubview(picture)

        let blank = UIHostingController(rootView: EmptySpace(session: session, window: model) { [weak self] in self?.act($0) })
        addChild(blank)
        blank.view.frame = stage.bounds
        blank.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blank.view.backgroundColor = .clear
        blank.view.isHidden = true
        stage.addSubview(blank.view)
        blank.didMove(toParent: self)
        empty = blank

        refreshChrome()
    }

    private func embed<V: View>(_ root: V) -> UIHostingController<V> {
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = Palette.UI.ground
        addChild(host)
        stack.addArrangedSubview(host.view)
        host.didMove(toParent: self)
        return host
    }

    /// Which bars show, from Settings and the page.
    private func refreshChrome() {
        let preferences = Session.shared.preferences
        let url = page?.view.url ?? model.tabID.flatMap { Session.shared.workspace.tab($0)?.url }
        model.showsAddress = AddressVisibility.shows(
            mode: preferences.address, url: url, passwordField: page?.passwordField ?? false,
            editing: model.editingAddress, failed: page?.failure != nil
        )
        topBar?.view.isHidden = !preferences.tabBar
        addressBar?.view.isHidden = !model.showsAddress
        bannerBar?.view.isHidden = model.banner == nil
        showDiagnostics(preferences.diagnostics)
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
        detach()
        let made = session.pages.page(for: record, in: owner)
        attach(made.page, thawed: made.thawed)
        model.spaceID = owner
        model.tabID = id
        session.change { $0.select(id) }
        pageDidChange(made.page)
        focusPage()
        session.pages.enforce()
    }

    func showSpace(_ space: UUID) {
        let session = Session.shared
        guard let target = session.workspace.space(space) else { return }
        let choice = [target.selected].compactMap { $0 }.first { session.browser(showing: $0) == nil }
            ?? target.tabs.first { session.browser(showing: $0.id) == nil }?.id
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
        empty?.view.isHidden = false
        refreshChrome()
        updateSceneTitle()
    }

    private func attach(_ page: Page, thawed: Bool) {
        page.host = self
        page.view.frame = stage.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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
        guard let page else { return }
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
        guard let page, presentedViewController == nil, !model.editingAddress else { return }
        _ = page.view.becomeFirstResponder()
    }

    // MARK: PageHost

    func pageDidChange(_ page: Page) {
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
        connected && page === self.page
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
        pageDidChange(child)
        focusPage()
        session.pages.enforce()
        return child.view
    }

    func pageDidClose(_ page: Page) {
        guard page === self.page else { return }
        Session.shared.closeTab(page.tab)
    }

    var presenter: UIViewController? {
        var top: UIViewController = self
        while let next = top.presentedViewController { top = next }
        return top
    }

    // MARK: Commands

    override var keyCommands: [UIKeyCommand]? {
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
        }
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
            if session.browser(showing: next) == nil {
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

    private func renameSpace(_ id: UUID) {
        guard let space = Session.shared.workspace.space(id) else { return }
        Dialogs.name(title: "Rename Space", message: nil, placeholder: space.name, initial: space.name,
                     on: presenter ?? self) { name in
            guard let name else { return }
            Session.shared.change { $0.renameSpace(id, to: name) }
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
        case .renameSpace(let space): renameSpace(space)
        case .removeSpace(let space): removeSpace(space)
        case .setSymbol(let space, let symbol): session.change { $0.setSymbol(space, to: symbol) }
        case .moveTab(let tab, let space): session.moveTab(tab, to: space)
        case .tabInNewWindow(let tab):
            if model.tabID == tab {
                let next = session.workspace.neighbour(of: tab, by: 1)
                if let next, next != tab, session.browser(showing: next) == nil {
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
        }
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
        let settings = UIHostingController(rootView: SettingsView(session: Session.shared) { [weak self] in
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
