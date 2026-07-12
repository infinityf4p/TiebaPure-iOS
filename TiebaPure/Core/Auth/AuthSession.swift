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

enum AuthSessionError: Error, Equatable {
    case missingRequiredCookies
    case untrustedCookie
    case disallowedNavigation
}

struct AuthSession {
    static let loginURL = URL(
        string: "https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine"
    )!

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
            "com.baidu.tieba://"
        ]
        return appMarkers.contains { marker in
            text.contains(marker) || decodedText.contains(marker)
        }
    }

    static func shouldAttemptCookieValidation(on url: URL) -> Bool {
        isSuccessURL(url)
    }

    static func hasRequiredCookies(_ cookies: [HTTPCookie]) -> Bool {
        let valuesByName = preferredCookieValues(from: cookies)
        let hasBDUSS = valuesByName["BDUSS"] != nil || valuesByName["BDUSS_BFESS"] != nil
        return hasBDUSS && valuesByName["STOKEN"] != nil
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
        guard allowedNames.contains(cookie.name.uppercased()),
              cookie.isSecure,
              cookie.value.isEmpty == false,
              cookie.value.rangeOfCharacter(from: .newlines) == nil,
              cookie.value.contains(";") == false,
              cookie.expiresDate.map({ $0 > Date() }) ?? true else {
            return false
        }

        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let allowedCookieDomains = Set(["baidu.com", "tieba.baidu.com"])
        guard allowedCookieDomains.contains(domain) else {
            return false
        }
        return cookie.path.isEmpty || cookie.path.hasPrefix("/")
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
