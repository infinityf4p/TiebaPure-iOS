import Foundation

/// Runs the daily check-in across the account's followed forums.
///
/// The requests are issued one at a time on purpose: a burst of writes from a
/// third-party client is exactly what the service rate-limits, and a check-in
/// that silently drops half the forums is worse than one that takes a few
/// seconds longer. Forums the guide already reports as signed today are skipped
/// without a request, so a long followed list does not become a long serial run
/// — and the run publishes its counters, because a spinner alone cannot tell a
/// two-second run from a two-minute one.
@MainActor
final class ForumSignCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastSummary: ForumSignRunSummary?
    @Published private(set) var lastError: String?
    /// Live counters for the run the UI is presenting, nil when nothing runs.
    @Published private(set) var progress: ForumSignProgress?

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
            let runStarted = Date()
            do {
                var stepStarted = Date()
                let forums = try await api.followedForums(account: account)
                try Task.checkCancellation()
                let listSeconds = Date().timeIntervalSince(stepStarted)

                // Today's check-in only has work for the forums the guide does
                // not already mark as signed. Sending those writes anyway costs
                // one throttled round trip per forum to learn what the service
                // has just said.
                stepStarted = Date()
                let alreadySignedToday = await signedForumIDs(account: account)
                try Task.checkCancellation()
                let statusSeconds = Date().timeIntervalSince(stepStarted)

                let pending = forums.filter { alreadySignedToday.contains($0.id) == false }
                summary.alreadySignedCount += forums.count - pending.count
                var completed = forums.count - pending.count
                publishProgress(
                    completed: completed,
                    total: forums.count,
                    session: session,
                    summary: summary
                )
                // The per-step timings are the only way to tell a slow list, a
                // slow guide and a slow write apart from the exported log.
                await AppLog.shared.record(
                    .info,
                    "一键签到",
                    "关注 \(forums.count) 个，已签 \(summary.alreadySignedCount) 个，待签 \(pending.count) 个；"
                        + "关注列表 \(Self.seconds(listSeconds))，签到状态 \(Self.seconds(statusSeconds))"
                )

                // One write token for the whole run: the login handshake that
                // produces it costs more than the check-in write itself, and
                // doing it per forum is what made a long list feel stuck.
                //
                // It is also the single most expensive step of the run, so a
                // run with nothing to write must not pay for it: with every
                // forum already signed the loop below is empty, and resolving
                // the token anyway turned "nothing to do" into a spinner that
                // sat there for the whole handshake.
                let tbs: String
                stepStarted = Date()
                if pending.isEmpty {
                    tbs = ""
                    await AppLog.shared.record(
                        .info,
                        "一键签到",
                        "无待签贴吧，跳过写令牌解析，耗时 "
                            + "\(Self.seconds(Date().timeIntervalSince(stepStarted)))"
                    )
                } else {
                    tbs = (try? await api.signingTBS(account: account)) ?? ""
                    try Task.checkCancellation()
                    await AppLog.shared.record(
                        .info,
                        "一键签到",
                        "写令牌\(tbs.isEmpty ? "未取到，逐吧解析" : "已就绪，本轮回用")，"
                            + "耗时 \(Self.seconds(Date().timeIntervalSince(stepStarted)))"
                    )
                }

                let signingStarted = Date()
                for (index, forum) in pending.enumerated() {
                    if index > 0 {
                        try await Task.sleep(for: requestSpacing)
                    }
                    do {
                        try Task.checkCancellation()
                        publishProgress(
                            completed: completed,
                            total: forums.count,
                            currentForumName: forum.displayName,
                            session: session,
                            summary: summary
                        )
                        let result = try await api.signForum(account: account, forum: forum, tbs: tbs)
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
                        await AppLog.shared.recordError(
                            "一键签到",
                            "\(forum.displayName) 签到失败",
                            error: error
                        )
                    }
                    completed += 1
                    publishProgress(
                        completed: completed,
                        total: forums.count,
                        session: session,
                        summary: summary
                    )
                }
                let signingSeconds = Date().timeIntervalSince(signingStarted)
                await AppLog.shared.record(
                    .info,
                    "一键签到",
                    "完成：成功 \(summary.signedCount)，已签过 \(summary.alreadySignedCount)，"
                        + "失败 \(summary.failedForumNames.count)；写请求耗时 "
                        + "\(Self.seconds(signingSeconds))，整轮 \(Self.seconds(Date().timeIntervalSince(runStarted)))"
                )
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

    /// One line for the diagnostic log: a run's cost only makes sense as a
    /// number, and "slow" without seconds is not something to act on.
    private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.1fs", max(interval, 0))
    }

    /// Only the session the UI is showing drives the visible counters; a run for
    /// a replaced login keeps its own state until it is drained.
    private func publishProgress(
        completed: Int,
        total: Int,
        currentForumName: String? = nil,
        session: AccountSessionIdentity,
        summary: ForumSignRunSummary
    ) {
        guard presentationSession == session else { return }
        progress = ForumSignProgress(
            completed: completed,
            total: total,
            currentForumName: currentForumName,
            signedCount: summary.signedCount,
            alreadySignedCount: summary.alreadySignedCount,
            failedCount: summary.failedForumNames.count
        )
    }

    /// Forum IDs the service already reports as signed today.
    ///
    /// A service without the guide listing cannot answer, and an unknown sign
    /// state must not read as "everything is done": signing an already-signed
    /// forum is a harmless no-op, so the run attempts every forum instead and
    /// leaves a trace in the diagnostic log.
    private func signedForumIDs(account: Account) async -> Set<Int64> {
        do {
            let statuses = try await api.followedForumStatuses(account: account)
            return Set(statuses.filter(\.isSignedToday).map(\.forumID))
        } catch is CancellationError {
            return []
        } catch {
            await AppLog.shared.recordError(
                "一键签到",
                "读取今日签到状态失败，本次不跳过任何贴吧",
                error: error
            )
            return []
        }
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
        progress = nil
        if outcome.wasCancelled == false {
            lastSummary = outcome.summary
            lastError = outcome.errorMessage
        }
    }
}
