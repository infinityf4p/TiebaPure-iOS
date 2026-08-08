import Combine
import Foundation

/// Runs the daily check-in across the account's followed forums.
///
/// The requests are issued one at a time on purpose: a burst of writes from a
/// third-party client is exactly what the service rate-limits, and a check-in
/// that silently drops half the forums is worse than one that takes a few
/// seconds longer.
@MainActor
final class ForumSignCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastSummary: ForumSignRunSummary?
    @Published private(set) var lastError: String?

    private let api: any TiebaAPIService
    private let settings: ForumSignSettingsStore
    private let requestSpacing: Duration
    private struct RunOutcome {
        let summary: ForumSignRunSummary
        let errorMessage: String?
        let wasCancelled: Bool
    }

    private struct Run {
        let id: UUID
        let task: Task<RunOutcome, Never>
    }

    private var runs: [AccountSessionIdentity: Run] = [:]
    private var presentationSession: AccountSessionIdentity?
    private var globalInvalidationCount = 0
    private var sessionInvalidationCounts: [AccountSessionIdentity: Int] = [:]

    init(
        api: any TiebaAPIService,
        settings: ForumSignSettingsStore,
        requestSpacing: Duration = .milliseconds(350)
    ) {
        self.api = api
        self.settings = settings
        self.requestSpacing = requestSpacing
    }

    /// Signs every followed forum. Concurrent invocations from the same login
    /// session join its run instead of doubling the write traffic. A replacement
    /// login never joins the old session's task, even when both accounts share a
    /// user ID.
    @discardableResult
    func signAllFollowedForums(account: Account) async -> ForumSignRunSummary {
        let session = account.sessionIdentity
        guard canRun(session: session) else { return .empty }
        if let existing = runs[session] {
            let outcome = await existing.task.value
            finishRun(id: existing.id, session: session, outcome: outcome)
            return outcome.summary
        }

        presentationSession = session
        lastError = nil
        let runID = UUID()
        let task = Task { @MainActor [api, settings, requestSpacing] in
            var summary = ForumSignRunSummary.empty
            do {
                let forums = try await api.followedForums(account: account)
                try Task.checkCancellation()
                for (index, forum) in forums.enumerated() {
                    if index > 0 {
                        try await CompatibleTaskSleep.duration(requestSpacing)
                    }
                    do {
                        try Task.checkCancellation()
                        let result = try await api.signForum(account: account, forum: forum)
                        try Task.checkCancellation()
                        if result.wasAlreadySigned {
                            summary.alreadySignedCount += 1
                        } else {
                            summary.signedCount += 1
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        summary.failedForumNames.append(forum.displayName)
                    }
                }
                // Only a run that reached every forum counts as today's run;
                // otherwise tomorrow's automatic attempt would be skipped after
                // a partial failure.
                try Task.checkCancellation()
                if summary.failedForumNames.isEmpty, summary.isEmpty == false {
                    settings.markRunCompleted(accountID: account.id)
                }
                return RunOutcome(
                    summary: summary,
                    errorMessage: nil,
                    wasCancelled: false
                )
            } catch is CancellationError {
                return RunOutcome(
                    summary: summary,
                    errorMessage: nil,
                    wasCancelled: true
                )
            } catch {
                return RunOutcome(
                    summary: summary,
                    errorMessage: ReaderErrorMessage.message(for: error),
                    wasCancelled: false
                )
            }
        }
        runs[session] = Run(id: runID, task: task)
        isRunning = true
        let outcome = await task.value
        finishRun(id: runID, session: session, outcome: outcome)
        return outcome.summary
    }

    /// The automatic path: at most one completed run per local day per account.
    func signAutomaticallyIfNeeded(account: Account?) async {
        guard let account,
              settings.automaticSignEnabled,
              settings.hasRunToday(accountID: account.id) == false else { return }
        await signAllFollowedForums(account: account)
    }

    func clearLastSummary() {
        lastSummary = nil
        lastError = nil
    }

    func isInvalidating(session: AccountSessionIdentity) -> Bool {
        canRun(session: session) == false
    }

    /// Closes the selected session (or every session) synchronously. Logout and
    /// account replacement establish all write barriers before awaiting drains.
    func establishInvalidationBarrier(session: AccountSessionIdentity? = nil) {
        if let session {
            sessionInvalidationCounts[session, default: 0] += 1
        } else {
            globalInvalidationCount += 1
        }
    }

    /// Cancels and waits for every covered run. Entries stay registered until
    /// their exact task exits, so a new run cannot overlap a cancelled one.
    func drainInvalidatedOperations(session: AccountSessionIdentity? = nil) async {
        while true {
            let matching = runs.filter { storedSession, _ in
                session == nil || storedSession == session
            }
            guard matching.isEmpty == false else { return }

            matching.values.forEach { $0.task.cancel() }
            var outcomes: [AccountSessionIdentity: RunOutcome] = [:]
            for (storedSession, run) in matching {
                outcomes[storedSession] = await run.task.value
            }
            for (storedSession, run) in matching {
                guard let outcome = outcomes[storedSession] else { continue }
                finishRun(
                    id: run.id,
                    session: storedSession,
                    outcome: outcome
                )
            }
        }
    }

    func beginInvalidation(session: AccountSessionIdentity? = nil) async {
        establishInvalidationBarrier(session: session)
        await drainInvalidatedOperations(session: session)
    }

    func endInvalidation(session: AccountSessionIdentity? = nil) {
        if let session {
            guard let count = sessionInvalidationCounts[session] else { return }
            if count > 1 {
                sessionInvalidationCounts[session] = count - 1
            } else {
                sessionInvalidationCounts[session] = nil
            }
        } else {
            globalInvalidationCount = max(0, globalInvalidationCount - 1)
        }
    }

    func cancel() {
        runs.values.forEach { $0.task.cancel() }
    }

    private func canRun(session: AccountSessionIdentity) -> Bool {
        globalInvalidationCount == 0 && sessionInvalidationCounts[session] == nil
    }

    private func finishRun(
        id: UUID,
        session: AccountSessionIdentity,
        outcome: RunOutcome
    ) {
        guard runs[session]?.id == id else { return }
        runs[session] = nil
        isRunning = runs.isEmpty == false
        guard presentationSession == session else { return }
        if outcome.wasCancelled == false {
            lastSummary = outcome.summary
            lastError = outcome.errorMessage
        }
    }
}
