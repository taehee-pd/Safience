import Foundation

/// Localized names used by native menus and command results. User data is never a key.
public enum BrowserText {
    public static func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    /// The language owns the count's word order and plural rules.
    public static func tabCount(_ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString("tabs.count", bundle: .module, comment: "Number of browser tabs"), count)
    }

    static var resourceBundle: Bundle { .module }
}
