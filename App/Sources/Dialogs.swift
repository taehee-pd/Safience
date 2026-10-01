import UIKit
import WebKit

/// The questions a page or the app asks, as the system's alerts.
@MainActor
enum Dialogs {
    /// A page's alert, confirm or prompt is titled with the site asking, so
    /// a frame from another site can't speak as the page around it.
    private static func title(for frame: WKFrameInfo) -> String {
        let host = frame.securityOrigin.host
        return host.isEmpty ? "This page says" : "\(host) says"
    }

    static func alert(_ message: String, from frame: WKFrameInfo, on presenter: UIViewController,
                      done: @escaping @MainActor () -> Void) {
        let alert = UIAlertController(title: title(for: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done() })
        presenter.present(alert, animated: true)
    }

    static func confirm(_ message: String, from frame: WKFrameInfo, on presenter: UIViewController,
                        done: @escaping @MainActor (Bool) -> Void) {
        let alert = UIAlertController(title: title(for: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done(true) })
        presenter.present(alert, animated: true)
    }

    static func prompt(_ prompt: String, defaultText: String?, from frame: WKFrameInfo, on presenter: UIViewController,
                       done: @escaping @MainActor (String?) -> Void) {
        let alert = UIAlertController(title: title(for: frame), message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            done(alert?.textFields?.first?.text ?? "")
        })
        presenter.present(alert, animated: true)
    }

    /// A server asking for a name and password itself (HTTP authentication),
    /// as some companies' single sign-on does.
    static func credentials(for space: URLProtectionSpace, on presenter: UIViewController,
                            done: @escaping @MainActor (URLCredential?) -> Void) {
        let realm = space.realm.map { " (\($0))" } ?? ""
        let alert = UIAlertController(title: "Sign in to \(space.host)",
                                      message: "The server asks for your name and password\(realm).",
                                      preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "Name"
            $0.textContentType = .username
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addTextField {
            $0.placeholder = "Password"
            $0.textContentType = .password
            $0.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(nil) })
        alert.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak alert] _ in
            let fields = alert?.textFields ?? []
            let user = fields.first?.text ?? ""
            let password = fields.dropFirst().first?.text ?? ""
            done(URLCredential(user: user, password: password, persistence: .forSession))
        })
        presenter.present(alert, animated: true)
    }

    /// A name for something new or renamed: a space.
    static func name(title: String, message: String?, placeholder: String, initial: String,
                     on presenter: UIViewController, done: @escaping @MainActor (String?) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = placeholder
            $0.text = initial
            $0.autocapitalizationType = .words
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            done(alert?.textFields?.first?.text ?? "")
        })
        presenter.present(alert, animated: true)
    }

    static func confirmRemoval(of space: String, tabs: Int, on presenter: UIViewController,
                               done: @escaping @MainActor (Bool) -> Void) {
        let alert = UIAlertController(
            title: "Remove “\(space)”?",
            message: "Its \(tabs) \(tabs == 1 ? "tab closes" : "tabs close"), and its sign-ins, cookies and site data are erased.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in done(true) })
        presenter.present(alert, animated: true)
    }

    static func notice(title: String, message: String, on presenter: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}
