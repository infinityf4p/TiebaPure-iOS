import Foundation
import Darwin

enum TiebaURL {
    static func image(_ value: String?) -> URL? { secureRemoteURL(value) }
    static func video(_ value: String?) -> URL? { secureRemoteURL(value) }
    static func webpage(_ value: String?) -> URL? { secureRemoteURL(value) }

    static func make(_ value: String?) -> URL? {
        secureRemoteURL(value)
    }

    private static func secureRemoteURL(_ value: String?) -> URL? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
            return nil
        }

        if text.hasPrefix("//") {
            text = "https:" + text
        }

        guard let components = URLComponents(string: text),
              components.user == nil,
              components.password == nil else {
            return nil
        }

        guard components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host.isEmpty == false,
              isLocalOrPrivate(host: host) == false else {
            return nil
        }

        return components.url
    }

    static func avatar(_ value: String?) -> URL? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
            return nil
        }

        if text.hasPrefix("//") {
            text = "https:" + text
        }

        if text.hasPrefix("https://tb.himg.baidu.com/") {
            text = text
                .replacingOccurrences(of: "https://tb.himg.baidu.com/", with: "https://himg.bdimg.com/")
            return image(text)
        }

        if let url = image(text), url.scheme != nil {
            return url
        }

        // A rejected absolute URL is not a portrait identifier. Without this
        // guard an insecure URL could be embedded as a harmless-looking path
        // under the avatar CDN instead of being rejected explicitly.
        if URLComponents(string: text)?.scheme != nil || text.contains("://") {
            return nil
        }

        return image("https://himg.bdimg.com/sys/portrait/item/\(text)")
    }

    private static func isLocalOrPrivate(host: String) -> Bool {
        let value = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
            .lowercased()
        if value == "localhost"
            || value.hasSuffix(".localhost")
            || value.hasSuffix(".local")
            || value.hasSuffix(".internal")
            || value.hasSuffix(".lan")
            || value == "home.arpa"
            || value.hasSuffix(".home.arpa")
            || value.contains("%") {
            return true
        }

        if let bytes = ipv4Bytes(value) {
            return isNonPublicIPv4(bytes)
        }

        if let bytes = ipv6Bytes(value) {
            if bytes.allSatisfy({ $0 == 0 }) { return true }
            if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return true }

            // IPv4-compatible and IPv4-mapped IPv6 literals.
            let compatiblePrefix = bytes.prefix(12).allSatisfy { $0 == 0 }
            let mappedPrefix = bytes.prefix(10).allSatisfy { $0 == 0 }
                && bytes[10] == 0xff
                && bytes[11] == 0xff
            if compatiblePrefix || mappedPrefix {
                return isNonPublicIPv4(Array(bytes.suffix(4)))
            }

            // Unique-local, link-local, deprecated site-local and multicast.
            if bytes[0] & 0xfe == 0xfc { return true }
            if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 { return true }
            if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0xc0 { return true }
            if bytes[0] == 0xff { return true }

            // NAT64 translations must not be usable to reach a private IPv4
            // destination through an otherwise public-looking IPv6 literal.
            let wellKnownNAT64 = bytes.prefix(12).elementsEqual([0x00, 0x64, 0xff, 0x9b] + Array(repeating: 0, count: 8))
            let localNAT64 = bytes.prefix(6).elementsEqual([0x00, 0x64, 0xff, 0x9b, 0x00, 0x01])
            if (wellKnownNAT64 || localNAT64), isNonPublicIPv4(Array(bytes.suffix(4))) {
                return true
            }
        }

        return false
    }

    private static func ipv4Bytes(_ value: String) -> [UInt8]? {
        var address = in_addr()
        let parsed = value.withCString { inet_aton($0, &address) }
        guard parsed == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0.prefix(4)) }
    }

    private static func ipv6Bytes(_ value: String) -> [UInt8]? {
        var address = in6_addr()
        let parsed = value.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0.prefix(16)) }
    }

    private static func isNonPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        switch (bytes[0], bytes[1], bytes[2]) {
        case (0, _, _), (10, _, _), (127, _, _), (169, 254, _), (192, 168, _):
            return true
        case (100, 64...127, _), (172, 16...31, _), (198, 18...19, _):
            return true
        case (192, 0, 0), (192, 0, 2), (192, 88, 99), (198, 51, 100), (203, 0, 113):
            return true
        default:
            return bytes[0] >= 224
        }
    }
}
