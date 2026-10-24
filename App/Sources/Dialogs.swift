import PadCore
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
        let reply = DialogReply(fallback: (), completion: { _ in done() })
        let alert = UIAlertController(title: title(for: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in reply(()) })
        present(alert, on: presenter, reply: reply)
    }

    static func confirm(_ message: String, from frame: WKFrameInfo, on presenter: UIViewController,
                        done: @escaping @MainActor (Bool) -> Void) {
        let reply = DialogReply(fallback: false, completion: done)
        let alert = UIAlertController(title: title(for: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in reply(true) })
        present(alert, on: presenter, reply: reply)
    }

    static func prompt(_ prompt: String, defaultText: String?, from frame: WKFrameInfo, on presenter: UIViewController,
                       done: @escaping @MainActor (String?) -> Void) {
        let reply = DialogReply<String?>(fallback: nil, completion: done)
        let alert = UIAlertController(title: title(for: frame), message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            reply(alert?.textFields?.first?.text ?? "")
        })
        present(alert, on: presenter, reply: reply)
    }

    /// A server asking for a name and password itself (HTTP authentication),
    /// as some companies' single sign-on does.
    static func credentials(for space: URLProtectionSpace, previousFailures: Int = 0, on presenter: UIViewController,
                            done: @escaping @MainActor (URLCredential?) -> Void) {
        let reply = DialogReply<URLCredential?>(fallback: nil, completion: done)
        let realm = space.realm.map { " (\($0))" } ?? ""
        var message = "The server asks for your name and password\(realm)."
        if previousFailures > 0 { message = "The name or password was not accepted. Try again.\n\n" + message }
        if space.protocol?.lowercased() != "https" {
            message += "\n\nThis connection is not encrypted. Your name and password could be read by others on the network."
        }
        let alert = UIAlertController(title: "Sign in to \(space.host)",
                                      message: message,
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
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply(nil) })
        alert.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak alert] _ in
            let fields = alert?.textFields ?? []
            let user = fields.first?.text ?? ""
            let password = fields.dropFirst().first?.text ?? ""
            reply(URLCredential(user: user, password: password, persistence: .forSession))
        })
        present(alert, on: presenter, reply: reply)
    }

    private static func present<Value>(_ alert: UIAlertController, on presenter: UIViewController,
                                       reply: DialogReply<Value>) {
        // A page can ask while its window is closing or another sheet is up.
        // UIKit rejects those presentations without invoking any alert action.
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed,
              presenter.presentedViewController == nil else {
            reply.cancel()
            return
        }
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
        let confirm = UIAlertAction(title: initial.isEmpty ? "Create" : "Rename", style: .default) { [weak alert] _ in
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            done(name)
        }
        confirm.isEnabled = !initial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        alert.addAction(confirm)
        alert.textFields?.first?.addAction(UIAction { [weak alert] _ in
            guard let alert else { return }
            let valid = !(alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            alert.actions.last?.isEnabled = valid
            alert.message = valid ? message : [message, "Enter a name."].compactMap { $0 }.joined(separator: "\n\n")
        }, for: .editingChanged)
        presenter.present(alert, animated: true)
    }

    static func confirmRemoval(of space: Space, on presenter: UIViewController,
                               done: @escaping @MainActor (Bool) -> Void) {
        let alert = UIAlertController(
            title: "Remove \(space.name)?",
            message: Sync.shared.spaceRemovalDescription(space),
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

/// WebKit requires a reply even when UIKit discards an alert without a tap.
/// Alert actions retain this reply until teardown; no action retains the alert.
@MainActor
final class DialogReply<Value> {
    private var completion: (@MainActor (Value) -> Void)?
    private let fallback: Value

    init(fallback: Value, completion: @escaping @MainActor (Value) -> Void) {
        self.fallback = fallback
        self.completion = completion
    }

    func callAsFunction(_ value: Value) {
        let done = completion
        completion = nil
        done?(value)
    }

    func cancel() { self(fallback) }

    /// Let go without an answer: the fallback, as cancel gives. The alert's
    /// actions release it on the main thread, with the alert. (An isolated
    /// deinit would say the same, but needs iOS 18.4; the app runs from 17.)
    deinit {
        guard let done = completion else { return }
        MainActor.assumeIsolated { done(fallback) }
    }
}
