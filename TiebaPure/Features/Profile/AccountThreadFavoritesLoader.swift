import Combine
import Foundation

/// Pages through the collection Baidu keeps for the account, so the favorites
/// screen can show it next to the on-device list instead of in a second place.
@MainActor
final class AccountThreadFavoritesLoader: ObservableObject {
    @Published private(set) var favorites: [AccountThreadFavorite] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false
    @Published private(set) var errorMessage: String?

    private var nextPage = 1
    private var hasMore = true
    private var generation = 0
    private var loadTask: Task<AccountThreadFavoritesPage, Error>?

    var canLoadMore: Bool { hasMore }

    func reload(account: Account?, api: any TiebaAPIService) async {
        cancel()
        nextPage = 1
        hasMore = true
        errorMessage = nil
        if favorites.isEmpty {
            didLoad = false
        }
        await loadMore(account: account, api: api, generation: generation)
    }

    func loadMore(account: Account?, api: any TiebaAPIService) async {
        await loadMore(account: account, api: api, generation: generation)
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        generation += 1
        isLoading = false
    }

    /// Drops threads the app just removed from the account, so the list does not
    /// have to round-trip before it matches what the user asked for.
    func remove(threadIDs: Set<Int64>) {
        guard threadIDs.isEmpty == false else { return }
        favorites.removeAll { threadIDs.contains($0.threadID) }
    }

    func reset() {
        cancel()
        favorites = []
        nextPage = 1
        hasMore = true
        didLoad = false
        errorMessage = nil
    }

    private func loadMore(
        account: Account?,
        api: any TiebaAPIService,
        generation requestGeneration: Int
    ) async {
        guard let account, isLoading == false, hasMore else { return }
        let requestedSession = account.sessionIdentity
        let requestedPage = nextPage
        isLoading = true
        errorMessage = nil

        do {
            let task = Task {
                try await api.accountThreadFavorites(account: account, page: requestedPage)
            }
            loadTask = task
            let page = try await task.value
            guard requestGeneration == generation,
                  requestedSession == account.sessionIdentity else { return }
            if requestedPage == 1 {
                favorites = page.favorites
            } else {
                let knownIDs = Set(favorites.map(\.threadID))
                favorites.append(
                    contentsOf: page.favorites.filter { knownIDs.contains($0.threadID) == false }
                )
            }
            hasMore = page.hasMore && page.favorites.isEmpty == false
            nextPage = requestedPage + 1
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            loadTask = nil
            isLoading = false
            return
        } catch {
            guard requestGeneration == generation,
                  requestedSession == account.sessionIdentity else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard requestGeneration == generation else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
    }
}
