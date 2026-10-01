import PadCore
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Session.shared.start()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// The menus, without the system's own (see Menus.swift).
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        Menus.build(builder)
    }
}

/// One window: Stage Manager can show several side by side, each its own
/// scene with its own space and tab (WindowState), each restored as it was.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var browser: Browser? {
        window?.rootViewController as? Browser
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let asked = connectionOptions.userActivities.first { $0.activityType == WindowState.activityType }
        let browser = Browser(state: WindowState(activity: asked ?? session.stateRestorationActivity))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = browser
        self.window = window
        window.makeKeyAndVisible()
        NotificationCenter.default.addObserver(self, selector: #selector(becameKey(_:)),
                                               name: UIWindow.didBecomeKeyNotification, object: window)
        if let url = connectionOptions.urlContexts.first?.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            browser.open(url)
        }
    }

    /// The keys go to the page whenever its window becomes the one you use:
    /// switching apps, clicking another Stage Manager window, closing a sheet.
    func sceneDidBecomeActive(_ scene: UIScene) {
        browser?.focusPage()
    }

    @objc private func becameKey(_ notification: Notification) {
        browser?.focusPage()
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        browser?.state.activity
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        browser?.disconnect()
        NotificationCenter.default.removeObserver(self)
    }

    /// A link opened with the app, from another app or the share sheet.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        browser?.open(url)
    }
}
