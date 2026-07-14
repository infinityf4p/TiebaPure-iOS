import Foundation

struct BaiduCookies: Equatable, Sendable {
    var bduss: String
    var stoken: String
    var baiduID: String?

    var minimalCookieHeader: String {
        var values = ["BDUSS=\(bduss)", "STOKEN=\(stoken)"]
        if let baiduID, baiduID.isEmpty == false {
            values.append("BAIDUID=\(baiduID)")
        }
        return values.joined(separator: "; ")
    }
}

enum BaiduCredentialPolicy {
    static let maximumCookieValueBytes = 4_096

    static func isValidCookieValue(_ value: String) -> Bool {
        guard value.isEmpty == false,
              value.utf8.count <= maximumCookieValueBytes else {
            return false
        }
        // Cookie request headers must stay within visible ASCII and may not
        // contain the semicolon delimiter. This also blocks CR/LF injection
        // from legacy or externally modified persisted account data.
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x21 && scalar.value <= 0x7E && scalar.value != 0x3B
        }
    }

    static func isValid(_ cookies: BaiduCookies) -> Bool {
        isValidCookieValue(cookies.bduss)
            && isValidCookieValue(cookies.stoken)
            && (cookies.baiduID.map(isValidCookieValue) ?? true)
    }

    static func isValid(_ account: Account) -> Bool {
        account.uid.isEmpty == false
            && isValidCookieValue(account.bduss)
            && isValidCookieValue(account.stoken)
            && (account.baiduID.map(isValidCookieValue) ?? true)
    }
}

enum AuthSessionError: Error, Equatable {
    case missingRequiredCookies
    case untrustedCookie
    case disallowedNavigation
}

enum BlockedLoginNavigationResolution: Equatable {
    case recoverOnTiebaWeb
    case ignore
    case reportError
}

struct AuthSession {
    static let loginCompletionURL = URL(string: "https://tieba.baidu.com/index/tbwise/mine")!
    static let loginURL: URL = {
        var components = URLComponents(string: "https://wappass.baidu.com/passport")!
        components.queryItems = [
            URLQueryItem(name: "login", value: nil),
            URLQueryItem(name: "u", value: loginCompletionURL.absoluteString)
        ]
        return components.url!
    }()

    static func isSuccessURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              ["tieba.baidu.com", "tiebac.baidu.com"].contains(host),
              url.port == nil || url.port == 443,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return url.path == "/index/tbwise/mine" || url.path == "/index/tbwise/mine/"
    }

    static func isAllowedLoginURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              url.port == nil || url.port == 443,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return host == "baidu.com" || host.hasSuffix(".baidu.com")
    }

    static func isInertLoginDocumentURL(_ url: URL) -> Bool {
        url.absoluteString.caseInsensitiveCompare("about:blank") == .orderedSame
    }

    static func isExternalAppRedirectURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        let webSchemes = ["about", "http", "https"]
        guard webSchemes.contains(scheme) else {
            return true
        }

        let host = url.host?.lowercased() ?? ""
        if host == "apps.apple.com" || host == "itunes.apple.com" || host == "appsto.re" {
            return true
        }

        let text = url.absoluteString.lowercased()
        let decodedText = text.removingPercentEncoding ?? text
        let appMarkers = [
            "tbclient://",
            "bdtb://",
            "baidutieba://",
            "tieba://",
            "baiduboxapp://",
            "com.baidu.tieba",
            "id477927812"
        ]
        return appMarkers.contains { marker in
            text.contains(marker) || decodedText.contains(marker)
        }
    }

    static func shouldAttemptCookieValidation(on url: URL) -> Bool {
        isSuccessURL(url)
    }

    /// The official Tieba app claims the HTTPS completion address as a
    /// Universal Link. Capture it as an authentication signal, but never let
    /// WebKit render or hand it to the operating system.
    static func shouldCaptureCompletionWithoutRendering(_ url: URL) -> Bool {
        isSuccessURL(url)
    }

    static func blockedNavigationResolution(
        for url: URL,
        hasPrimaryLoginCookie: Bool,
        isUserInitiated: Bool
    ) -> BlockedLoginNavigationResolution {
        if hasPrimaryLoginCookie {
            return .recoverOnTiebaWeb
        }
        if isExternalAppRedirectURL(url) || isUserInitiated == false {
            return .ignore
        }
        return .reportError
    }

    static func hasPrimaryLoginCookie(_ cookies: [HTTPCookie]) -> Bool {
        let valuesByName = preferredCookieValues(from: cookies)
        return valuesByName["BDUSS"] != nil || valuesByName["BDUSS_BFESS"] != nil
    }

    static func hasRequiredCookies(_ cookies: [HTTPCookie]) -> Bool {
        let valuesByName = preferredCookieValues(from: cookies)
        let hasBDUSS = valuesByName["BDUSS"] != nil || valuesByName["BDUSS_BFESS"] != nil
        return hasBDUSS && valuesByName["STOKEN"] != nil
    }

    /// Baidu currently returns the primary login cookie without the Secure
    /// attribute on iOS, even though it is delivered during an HTTPS-only
    /// login flow. Keep the general cookie policy strict and apply this narrow
    /// compatibility upgrade only after WebKit has requested the exact,
    /// trusted Tieba completion URL. The ephemeral login web view rejects all
    /// HTTP navigation, and the resulting credentials are sent only by the
    /// HTTPS-only API client.
    static func cookiesForApprovedHTTPSCompletion(
        _ cookies: [HTTPCookie],
        completionURL: URL
    ) -> [HTTPCookie] {
        guard isSuccessURL(completionURL) else { return cookies }

        return cookies.map { cookie in
            guard shouldUpgradeLegacyBaiduCookie(cookie) else { return cookie }

            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path.isEmpty ? "/" : cookie.path,
                .secure: "TRUE"
            ]
            if let expiresDate = cookie.expiresDate {
                properties[.expires] = expiresDate
            }
            return HTTPCookie(properties: properties) ?? cookie
        }
    }

    static func extract(from cookies: [HTTPCookie]) throws -> BaiduCookies {
        let valuesByName = preferredCookieValues(from: cookies)

        guard let bduss = valuesByName["BDUSS"] ?? valuesByName["BDUSS_BFESS"],
              let stoken = valuesByName["STOKEN"] else {
            throw AuthSessionError.missingRequiredCookies
        }

        return BaiduCookies(
            bduss: bduss,
            stoken: stoken,
            baiduID: valuesByName["BAIDUID"]
        )
    }

    private static func preferredCookieValues(from cookies: [HTTPCookie]) -> [String: String] {
        var valuesByName: [String: String] = [:]
        let validCookies = cookies.filter(isTrustedCookie)
        for cookie in validCookies {
            let key = cookie.name.uppercased()
            if key == "STOKEN", let current = valuesByName[key] {
                let currentCookie = cookies.first { $0.name.uppercased() == key && $0.value == current }
                if isPreferredSToken(cookie, over: currentCookie) {
                    valuesByName[key] = cookie.value
                }
            } else {
                valuesByName[key] = cookie.value
            }
        }
        return valuesByName
    }

    private static func isTrustedCookie(_ cookie: HTTPCookie) -> Bool {
        let allowedNames = Set(["BDUSS", "BDUSS_BFESS", "STOKEN", "BAIDUID"])
        let name = cookie.name.uppercased()
        guard allowedNames.contains(name),
              cookie.isSecure,
              BaiduCredentialPolicy.isValidCookieValue(cookie.value),
              cookie.expiresDate.map({ $0 > Date() }) ?? true else {
            return false
        }

        let domain = normalizedDomain(cookie.domain.lowercased())
        guard allowedCookieDomains(for: name).contains(domain) else {
            return false
        }
        return cookie.path.isEmpty || cookie.path.hasPrefix("/")
    }

    private static func shouldUpgradeLegacyBaiduCookie(_ cookie: HTTPCookie) -> Bool {
        let upgradableNames = Set(["BDUSS", "BDUSS_BFESS", "BAIDUID"])
        let name = cookie.name.uppercased()
        return cookie.isSecure == false
            && upgradableNames.contains(name)
            && normalizedDomain(cookie.domain.lowercased()) == "baidu.com"
            && BaiduCredentialPolicy.isValidCookieValue(cookie.value)
            && (cookie.expiresDate.map { $0 > Date() } ?? true)
            && (cookie.path.isEmpty || cookie.path.hasPrefix("/"))
    }

    private static func allowedCookieDomains(for name: String) -> Set<String> {
        switch name {
        case "STOKEN":
            return ["baidu.com", "tieba.baidu.com", "wappass.baidu.com", "passport.baidu.com"]
        case "BDUSS", "BDUSS_BFESS":
            return ["baidu.com", "tieba.baidu.com"]
        case "BAIDUID":
            return ["baidu.com"]
        default:
            return []
        }
    }

    private static func isPreferredSToken(_ candidate: HTTPCookie, over current: HTTPCookie?) -> Bool {
        let candidateDomain = candidate.domain.lowercased()
        let currentDomain = current?.domain.lowercased() ?? ""
        let candidateIsTieba = normalizedDomain(candidateDomain) == "tieba.baidu.com"
        let currentIsTieba = normalizedDomain(currentDomain) == "tieba.baidu.com"
        if candidateIsTieba != currentIsTieba {
            return candidateIsTieba
        }
        return true
    }

    private static func normalizedDomain(_ domain: String) -> String {
        domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
