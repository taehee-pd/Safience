import PadCore
import UIKit
import WebKit

/// A window a page opened at a size of its own: a sign-in with Google, a
/// single sign-on, a share dialog. It opens over the page as a sheet, with
/// its address always in view (it is almost always a sign-in), and closes
/// by itself when the page closes it, handing its answer back to the page
/// that opened it.
@MainActor
final class Popup: UIViewController, PageHost {
    let page: Page
    /// Called once the pop-up is gone, to give the keys back to the page.
    var closed: (() -> Void)?
    private let lock = UIImageView()
    private let address = UILabel()

    init(opener: Page, configuration: WKWebViewConfiguration) {
        page = Page(tab: UUID(), space: opener.space, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        page.host = self
        modalPresentationStyle = .formSheet
        preferredContentSize = CGSize(width: 520, height: 680)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.UI.ground

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = Palette.UI.muted
        close.accessibilityLabel = "Close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)

        lock.contentMode = .scaleAspectFit
        lock.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11)
        address.font = .systemFont(ofSize: 13, weight: .medium)
        address.textColor = Palette.UI.ink
        address.lineBreakMode = .byTruncatingMiddle

        let header = UIStackView(arrangedSubviews: [lock, address, close])
        header.spacing = 8
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 8)
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let line = UIView()
        line.backgroundColor = Palette.UI.hairline

        for part in [header, line, page.view] as [UIView] {
            part.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(part)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safe.topAnchor),
            header.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Metrics.bar),
            close.widthAnchor.constraint(equalToConstant: 32),
            line.topAnchor.constraint(equalTo: header.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            page.view.topAnchor.constraint(equalTo: line.bottomAnchor),
            page.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pageDidChange(page)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = page.view.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        page.tearDown()
        closed?()
        closed = nil
    }

    func pageDidChange(_ page: Page) {
        guard isViewLoaded else { return }
        let url = page.view.url
        address.text = url.map(Destination.pretty) ?? "Loading…"
        let secure = page.view.hasOnlySecureContent
        lock.image = UIImage(systemName: secure ? "lock.fill" : "exclamationmark.triangle")
        lock.tintColor = secure ? Palette.UI.safe : Palette.UI.unsafe
        lock.isHidden = url == nil
    }

    func isShowing(_ page: Page) -> Bool {
        page === self.page && view.window != nil
    }

    /// A window opened from the pop-up opens in the pop-up.
    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { page.load(url) }
        return nil
    }

    /// A pop-up has no tabs: a ⌘-click goes there in the pop-up.
    func page(_ page: Page, openInNewTab url: URL, inFront: Bool) -> Bool {
        false
    }

    func pageDidClose(_ page: Page) {
        dismiss(animated: true)
    }

    var presenter: UIViewController? {
        self
    }
}
