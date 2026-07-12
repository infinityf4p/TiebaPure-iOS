import Foundation

struct SearchRoute: Identifiable, Hashable {
    var keyword: String

    var id: String {
        keyword
    }
}
