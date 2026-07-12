import Foundation

struct Account: Codable, Equatable, Identifiable, Sendable {
    var uid: String
    var name: String
    var displayName: String
    var portrait: String
    var bduss: String
    var stoken: String
    var baiduID: String?
    var tbs: String

    var id: String { uid }

    var portraitURL: URL? {
        TiebaURL.avatar(portrait)
    }

    /// Only the three validated cookies required by the read-only web API.
    /// The app deliberately never persists a browser's complete Cookie header.
    var minimalCookieHeader: String {
        var values = ["BDUSS=\(bduss)", "STOKEN=\(stoken)"]
        if let baiduID, baiduID.isEmpty == false {
            values.append("BAIDUID=\(baiduID)")
        }
        return values.joined(separator: "; ")
    }

    static let preview = Account(
        uid: "0",
        name: "Preview",
        displayName: "Preview",
        portrait: "",
        bduss: "",
        stoken: "",
        baiduID: nil,
        tbs: ""
    )
}
