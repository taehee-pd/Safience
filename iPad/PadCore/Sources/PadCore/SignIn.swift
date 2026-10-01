import Foundation

/// Sign-in pages, told from their address alone.
///
/// The address bar is hidden most of the time, to leave the page the whole
/// window, and always shown on a sign-in page so the host asking for a
/// password is in plain view (see `AddressVisibility`). The address is enough
/// to tell: no script has to look into the page, which on Google's sign-in
/// none may (see `HandsOff`). A page with a password field counts too, from
/// the bridge's report, wherever the bridge runs.
public enum SignIn {
    /// Identity providers' own sign-in hosts.
    static let hosts = [
        "accounts.google.com",
        "login.microsoftonline.com", "login.microsoft.com", "login.live.com",
        "appleid.apple.com", "idmsa.apple.com", "account.apple.com",
        "id.atlassian.com", "signin.aws.amazon.com", "login.salesforce.com",
        "accounts.zoho.com", "login.yahoo.com", "auth.openai.com",
    ]

    /// Single sign-on services, each on a subdomain per company
    /// (acme.okta.com).
    static let domains = [
        "okta.com", "oktapreview.com", "okta-emea.com", "auth0.com", "onelogin.com",
        "duosecurity.com", "pingone.com", "pingidentity.com", "jumpcloud.com",
    ]

    /// Whole path segments that name a sign-in step. Whole, so /author/
    /// and /loginsight/ are not sign-in pages.
    static let words: Set<String> = [
        "login", "log-in", "log_in", "signin", "sign-in", "sign_in", "signon", "sign-on",
        "signup", "sign-up", "sign_up", "sso", "saml", "saml2", "oauth", "oauth2",
        "authorize", "authenticate", "auth", "session", "sessions", "mfa", "2fa",
        "two-factor", "challenge", "verify", "password", "reset-password",
    ]

    public static func isSignInPage(_ url: URL?) -> Bool {
        guard let url, let host = Hosts.host(of: url) else { return false }
        if hosts.contains(where: { Hosts.host(host, isWithin: $0) }) { return true }
        if domains.contains(where: { Hosts.host(host, isWithin: $0) }) { return true }
        let segments = url.path().lowercased().split(separator: "/").map(String.init)
        if segments.contains(where: words.contains) { return true }
        // An OAuth or OpenID request carries both, wherever it is served.
        let names = Set(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.map { $0.name.lowercased() } ?? [])
        return names.contains("client_id") && names.contains("redirect_uri")
    }

    /// Google's answer to a sign-in it won't do in this app: "This browser or
    /// app may not be secure", or Error 403: disallowed_useragent. Read from
    /// the address, the one thing about a hands-off page the app may read.
    public static func googleRefused(_ url: URL?) -> Bool {
        guard let url, HandsOff.covers(url) else { return false }
        let path = url.path().lowercased()
        if path.contains("/signin/rejected") { return true }
        guard path.contains("/error"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return false }
        for item in items where item.name == "authError" {
            guard let value = item.value else { continue }
            if value.contains("disallowed_useragent") { return true }
            // The reason comes base64url-encoded inside a small message.
            if let data = Data(base64URL: value),
               String(decoding: data, as: UTF8.self).contains("disallowed_useragent") {
                return true
            }
        }
        return false
    }

    /// What the app says when Google refuses: the other ways in.
    public static let fallback = "Google doesn't allow signing in from this app. Go back and sign in with your email address, or with your company's single sign-on (SSO), on the site's own sign-in page."
}

extension Data {
    /// base64url, padding optional, as tokens in addresses are written.
    init?(base64URL text: String) {
        var plain = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while plain.count % 4 != 0 { plain += "=" }
        self.init(base64Encoded: plain)
    }
}

/// When the address bar shows.
public enum AddressMode: String, Codable, CaseIterable, Sendable {
    /// On sign-in pages, while it is being typed in, and when a page failed.
    case automatic
    case always
}

public enum AddressVisibility {
    public static func shows(mode: AddressMode, url: URL?, passwordField: Bool,
                             editing: Bool, failed: Bool) -> Bool {
        mode == .always || editing || failed || url == nil || passwordField || SignIn.isSignInPage(url)
    }
}
