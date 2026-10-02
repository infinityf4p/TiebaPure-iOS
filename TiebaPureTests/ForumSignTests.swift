import XCTest
@testable import TiebaPure

final class ForumSignTests: XCTestCase {
    private func makeScratchDefaults() throws -> UserDefaults {
        let name = "forum-sign-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private var account: Account {
        FixtureTiebaAPI.account
    }

    func testSignFieldsCarryCredentialsForumAndTBS() throws {
        let fields = try TiebaForumSignRequestFactory.signFields(
            account: account,
            forumID: 4242,
            forumName: "  合成吧  ",
            tbs: " abc123 ",
            requestBuilder: TiebaRequestBuilder(
                screenScale: 3,
                screenWidth: 1179,
                screenHeight: 2556,
                clientID: "fixtureclientid"
            ),
            timestamp: 1_700_000_000_000
        )

        XCTAssertEqual(fields["BDUSS"], account.bduss)
        XCTAssertEqual(fields["kw"], "合成吧", "吧名两侧空白必须去掉")
        XCTAssertEqual(fields["tbs"], "abc123")
        XCTAssertEqual(fields["fid"], "4242")
        XCTAssertNotNil(fields["_client_version"])
        XCTAssertNil(fields["sign"], "签名由 HTTP 客户端计算，请求工厂不应预先写入")
    }

    func testSignFieldsRejectEmptyForumNameAndTBS() {
        let builder = TiebaRequestBuilder(
            screenScale: 3,
            screenWidth: 1179,
            screenHeight: 2556,
            clientID: "fixtureclientid"
        )
        XCTAssertThrowsError(
            try TiebaForumSignRequestFactory.signFields(
                account: account,
                forumID: 1,
                forumName: "   ",
                tbs: "abc",
                requestBuilder: builder
            )
        ) { error in
            XCTAssertEqual(error as? ForumSignError, .missingForumName)
        }
        XCTAssertThrowsError(
            try TiebaForumSignRequestFactory.signFields(
                account: account,
                forumID: 1,
                forumName: "合成吧",
                tbs: "  ",
                requestBuilder: builder
            )
        ) { error in
            XCTAssertEqual(error as? TiebaMutationError, .missingTBS)
        }
    }

    func testSignFieldsOmitForumIDWhenUnknown() throws {
        let fields = try TiebaForumSignRequestFactory.signFields(
            account: account,
            forumID: 0,
            forumName: "合成吧",
            tbs: "abc",
            requestBuilder: TiebaRequestBuilder(
                screenScale: 3,
                screenWidth: 1179,
                screenHeight: 2556,
                clientID: "fixtureclientid"
            )
        )
        XCTAssertNil(fields["fid"], "没有吧 ID 时只按吧名签到，不能发送 fid=0")
    }

    func testAlreadySignedCodeIsAnOutcomeNotAFailure() {
        XCTAssertTrue(ForumSignResponsePolicy.isAlreadySigned(errorCode: 160002))
        XCTAssertFalse(ForumSignResponsePolicy.isAlreadySigned(errorCode: 0))
        XCTAssertFalse(ForumSignResponsePolicy.isAlreadySigned(errorCode: 1))
    }

    func testSignResponseDecodesStreakFromStringsOrNumbers() throws {
        let json = Data("""
        {
          "error_code": "0",
          "user_info": {
            "is_sign_in": "1",
            "sign_bonus_point": 8,
            "cont_sign_num": "4",
            "user_sign_rank": "12"
          }
        }
        """.utf8)

        let response = try JSONDecoder().decode(ForumSignResponseDTO.self, from: json)

        XCTAssertEqual(response.errorCode, 0)
        XCTAssertEqual(response.userInfo?.isSignedIn, true)
        XCTAssertEqual(response.userInfo?.bonusPoints, 8)
        XCTAssertEqual(response.userInfo?.continuousDays, 4)
        XCTAssertEqual(response.userInfo?.rank, 12)
    }

    @MainActor
    func testAutomaticRunHappensOncePerLocalDayPerAccount() throws {
        let defaults = try makeScratchDefaults()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ForumSignSettingsStore(
            defaults: defaults,
            calendar: .current,
            now: { now }
        )

        XCTAssertFalse(store.automaticSignEnabled, "自动签到默认关闭")
        store.setAutomaticSignEnabled(true)
        XCTAssertTrue(store.automaticSignEnabled)

        XCTAssertFalse(store.hasRunToday(accountID: "user-a"))
        store.markRunCompleted(accountID: "user-a")
        XCTAssertTrue(store.hasRunToday(accountID: "user-a"))
        XCTAssertFalse(
            store.hasRunToday(accountID: "user-b"),
            "另一个账号不应继承已签状态"
        )

        now = now.addingTimeInterval(24 * 60 * 60)
        XCTAssertFalse(store.hasRunToday(accountID: "user-a"), "跨天后需要重新签到")

        // The setting and the day stamp survive a fresh store over the same
        // defaults, which is what makes "每天第一次打开" work across launches.
        let reloaded = ForumSignSettingsStore(defaults: defaults, now: { now })
        XCTAssertTrue(reloaded.automaticSignEnabled)
        reloaded.markRunCompleted(accountID: "user-a")
        XCTAssertTrue(
            ForumSignSettingsStore(defaults: defaults, now: { now })
                .hasRunToday(accountID: "user-a")
        )
    }

    func testDayStampFollowsTheLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 2026-08-06 23:30 +08:00 and 00:30 the next day are different days
        // even though they are less than an hour apart.
        let lateEvening = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 6, hour: 23, minute: 30)
        )!
        let afterMidnight = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 7, hour: 0, minute: 30)
        )!

        XCTAssertEqual(ForumSignDayStamp.text(for: lateEvening, calendar: calendar), "2026-08-06")
        XCTAssertEqual(ForumSignDayStamp.text(for: afterMidnight, calendar: calendar), "2026-08-07")
    }

    func testSummaryTextReportsEveryOutcomeGroup() {
        XCTAssertEqual(
            ForumSignSummaryText.message(for: .empty),
            "没有可签到的贴吧。"
        )
        XCTAssertEqual(
            ForumSignSummaryText.message(for: ForumSignRunSummary(
                signedCount: 16,
                alreadySignedCount: 0,
                failedForumNames: []
            )),
            "成功签到 16 个吧。"
        )
        XCTAssertEqual(
            ForumSignSummaryText.message(for: ForumSignRunSummary(
                signedCount: 0,
                alreadySignedCount: 16,
                failedForumNames: []
            )),
            "16 个今天已签过。"
        )
        XCTAssertEqual(
            ForumSignSummaryText.message(for: ForumSignRunSummary(
                signedCount: 2,
                alreadySignedCount: 1,
                failedForumNames: ["甲吧", "乙吧", "丙吧", "丁吧"]
            )),
            "成功签到 2 个吧，1 个今天已签过，4 个失败（甲吧、乙吧、丙吧 等）。"
        )
    }

    func testProgressTextReportsTheCounterAndTheForumInFlight() {
        let running = ForumSignProgress(
            completed: 3,
            total: 12,
            currentForumName: "壁纸吧",
            signedCount: 2,
            alreadySignedCount: 1,
            failedCount: 0
        )

        XCTAssertEqual(ForumSignProgressText.counter(for: running), "3/12")
        XCTAssertEqual(ForumSignProgressText.currentForum(for: running), "正在签到：壁纸吧")
        XCTAssertFalse(running.isFinished)

        var idle = running
        idle.currentForumName = nil
        XCTAssertNil(ForumSignProgressText.currentForum(for: idle), "没有在签的吧时不显示这一行")

        var blank = running
        blank.currentForumName = "   "
        XCTAssertNil(ForumSignProgressText.currentForum(for: blank), "空白吧名同样不显示")

        var done = running
        done.completed = 12
        XCTAssertTrue(done.isFinished)
    }

    @MainActor
    func testCoordinatorSignsEveryFollowedForumAndRecordsTheDay() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let api = FixtureTiebaAPI(scenario: .success)
        let coordinator = ForumSignCoordinator(
            api: api,
            settings: settings,
            requestSpacing: .zero
        )

        let summary = await coordinator.signAllFollowedForums(account: account)

        XCTAssertEqual(summary.signedCount, 2)
        XCTAssertEqual(summary.alreadySignedCount, 0)
        XCTAssertTrue(summary.failedForumNames.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertTrue(settings.hasRunToday(accountID: account.id))

        // A second pass reports the repeat instead of counting new check-ins.
        let repeated = await coordinator.signAllFollowedForums(account: account)
        XCTAssertEqual(repeated.signedCount, 0)
        XCTAssertEqual(repeated.alreadySignedCount, 2)
    }

    @MainActor
    func testRunSkipsForumsTheGuideAlreadyReportsAsSignedToday() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let coordinator = ForumSignCoordinator(
            api: FixtureTiebaAPI(scenario: .signAlreadyDone),
            settings: settings,
            requestSpacing: .zero
        )

        let summary = await coordinator.signAllFollowedForums(account: account)

        XCTAssertEqual(summary.signedCount, 1, "只有今天未签到的那个吧才发请求")
        XCTAssertEqual(summary.alreadySignedCount, 1, "已签到的吧直接计入已签过")
        XCTAssertTrue(summary.failedForumNames.isEmpty)
        XCTAssertTrue(
            settings.hasRunToday(accountID: account.id),
            "全部已签到时也算今天跑过，否则明天之前会反复自动重试"
        )
    }

    @MainActor
    func testRunWithNothingToSignDoesNotResolveAWriteToken() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let api = FixtureTiebaAPI(scenario: .signAllDone)
        let coordinator = ForumSignCoordinator(
            api: api,
            settings: settings,
            requestSpacing: .zero
        )

        let summary = await coordinator.signAllFollowedForums(account: account)
        let tokenRequests = await api.signingTBSRequestCount()

        XCTAssertEqual(summary.signedCount, 0)
        XCTAssertEqual(summary.alreadySignedCount, 2, "两个吧都已签到，整轮没有写请求")
        XCTAssertTrue(summary.failedForumNames.isEmpty)
        XCTAssertEqual(
            tokenRequests,
            0,
            "没有待签贴吧时不应解析写令牌：那一步是登录握手，会让「无需签到」也卡住整轮"
        )
        XCTAssertTrue(
            settings.hasRunToday(accountID: account.id),
            "全部已签到时也算今天跑过，否则明天之前会反复自动重试"
        )
    }

    @MainActor
    func testRunResolvesTheWriteTokenOnceForTheWholeList() async throws {
        let defaults = try makeScratchDefaults()
        let api = FixtureTiebaAPI(scenario: .success)
        let coordinator = ForumSignCoordinator(
            api: api,
            settings: ForumSignSettingsStore(defaults: defaults),
            requestSpacing: .zero
        )

        let summary = await coordinator.signAllFollowedForums(account: account)
        let tokenRequests = await api.signingTBSRequestCount()

        XCTAssertEqual(summary.signedCount, 2)
        XCTAssertEqual(tokenRequests, 1, "整轮只应握手一次，而不是每个吧一次")
    }

    @MainActor
    func testRunPublishesProgressWhileSigningAndClearsItAfterwards() async throws {
        let defaults = try makeScratchDefaults()
        let coordinator = ForumSignCoordinator(
            api: FixtureTiebaAPI(scenario: .success, delayMilliseconds: 60),
            settings: ForumSignSettingsStore(defaults: defaults),
            requestSpacing: .zero
        )

        let run = Task { @MainActor in
            await coordinator.signAllFollowedForums(account: account)
        }

        var observed: ForumSignProgress?
        for _ in 0..<400 where observed == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
            observed = coordinator.progress
        }

        let progress = try XCTUnwrap(observed, "签到过程中应能读到进度")
        XCTAssertEqual(progress.total, 2)
        XCTAssertFalse(progress.isFinished, "总数 2 时中途不可能已经结束")

        _ = await run.value
        XCTAssertNil(coordinator.progress, "结束后进度清空，不再显示上一次的数字")
        XCTAssertFalse(coordinator.isRunning)
    }

    @MainActor
    func testAutomaticRunIsSkippedWhenDisabledOrAlreadyDoneToday() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let coordinator = ForumSignCoordinator(
            api: FixtureTiebaAPI(scenario: .success),
            settings: settings,
            requestSpacing: .zero
        )

        await coordinator.signAutomaticallyIfNeeded(account: account)
        XCTAssertNil(coordinator.lastSummary, "开关关闭时不应发起签到")

        settings.setAutomaticSignEnabled(true)
        await coordinator.signAutomaticallyIfNeeded(account: account)
        XCTAssertEqual(coordinator.lastSummary?.signedCount, 2)

        coordinator.clearLastSummary()
        await coordinator.signAutomaticallyIfNeeded(account: account)
        XCTAssertNil(coordinator.lastSummary, "同一天只自动执行一次")

        await coordinator.signAutomaticallyIfNeeded(account: nil)
        XCTAssertNil(coordinator.lastSummary, "未登录时不应发起签到")
    }

    @MainActor
    func testPartialFailureDoesNotConsumeTheDay() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let coordinator = ForumSignCoordinator(
            api: FixtureTiebaAPI(scenario: .signFailure),
            settings: settings,
            requestSpacing: .zero
        )

        let summary = await coordinator.signAllFollowedForums(account: account)

        XCTAssertEqual(summary.signedCount, 1)
        XCTAssertEqual(summary.failedForumNames.count, 1)
        XCTAssertFalse(
            settings.hasRunToday(accountID: account.id),
            "有失败的吧时不能记为今天已完成，否则明天之前不会再自动重试"
        )
    }

    @MainActor
    func testConcurrentRunsAreIsolatedByLoginSession() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let api = FixtureTiebaAPI(scenario: .success, delayMilliseconds: 40)
        let coordinator = ForumSignCoordinator(
            api: api,
            settings: settings,
            requestSpacing: .zero
        )
        let replacement = Account(
            uid: "84",
            name: "replacement",
            displayName: "替换账号",
            portrait: "",
            bduss: "replacement-bduss",
            stoken: "replacement-stoken",
            baiduID: "replacement-baiduid",
            tbs: "replacement-tbs"
        )

        let first = Task { @MainActor in
            await coordinator.signAllFollowedForums(account: account)
        }
        await Task.yield()
        let second = Task { @MainActor in
            await coordinator.signAllFollowedForums(account: replacement)
        }

        let firstSummary = await first.value
        let secondSummary = await second.value

        XCTAssertEqual(firstSummary.signedCount, 2)
        XCTAssertEqual(secondSummary.signedCount, 2)
        XCTAssertTrue(settings.hasRunToday(accountID: account.id))
        XCTAssertTrue(
            settings.hasRunToday(accountID: replacement.id),
            "新登录不能加入旧账号的签到任务"
        )
        XCTAssertFalse(coordinator.isRunning)
    }

    @MainActor
    func testConcurrentCallsFromSameSessionJoinOneRun() async throws {
        let defaults = try makeScratchDefaults()
        let coordinator = ForumSignCoordinator(
            api: FixtureTiebaAPI(scenario: .success, delayMilliseconds: 40),
            settings: ForumSignSettingsStore(defaults: defaults),
            requestSpacing: .zero
        )

        let first = Task { @MainActor in
            await coordinator.signAllFollowedForums(account: account)
        }
        await Task.yield()
        let second = Task { @MainActor in
            await coordinator.signAllFollowedForums(account: account)
        }
        let firstSummary = await first.value
        let secondSummary = await second.value

        XCTAssertEqual(firstSummary.signedCount, 2)
        XCTAssertEqual(secondSummary.signedCount, 2)
        XCTAssertEqual(
            firstSummary.signedCount + secondSummary.signedCount,
            4,
            "同一会话的调用应共享同一份结果，而不是各自发送签到写请求"
        )
    }

    @MainActor
    func testSessionInvalidationCancelsAndDrainsRunWithoutConsumingTheDay() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let coordinator = ForumSignCoordinator(
            api: FixtureTiebaAPI(scenario: .success),
            settings: settings,
            requestSpacing: .milliseconds(500)
        )
        let run = Task { @MainActor in
            await coordinator.signAllFollowedForums(account: account)
        }

        try await Task.sleep(for: .milliseconds(100))
        await coordinator.beginInvalidation(session: account.sessionIdentity)
        let summary = await run.value

        XCTAssertEqual(summary.signedCount, 1, "夹具应在第二个吧前的间隔中被取消")
        XCTAssertFalse(settings.hasRunToday(accountID: account.id))
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertTrue(coordinator.isInvalidating(session: account.sessionIdentity))

        let blockedSummary = await coordinator.signAllFollowedForums(account: account)
        XCTAssertEqual(blockedSummary, .empty)
        coordinator.endInvalidation(session: account.sessionIdentity)

        let completed = await coordinator.signAllFollowedForums(account: account)
        XCTAssertEqual(completed.signedCount, 1)
        XCTAssertEqual(completed.alreadySignedCount, 1)
        XCTAssertTrue(settings.hasRunToday(accountID: account.id))
    }

    @MainActor
    func testLogoutDrainsSignRunBeforeClearingSessionArtifacts() async throws {
        let defaults = try makeScratchDefaults()
        let settings = ForumSignSettingsStore(defaults: defaults)
        let coordinator = ForumSignCoordinator(
            api: FixtureTiebaAPI(scenario: .success),
            settings: settings,
            requestSpacing: .milliseconds(500)
        )
        let accountStore = AccountStore(service: MemoryAccountStoreService())
        try await accountStore.save(account)
        let cleaner = ForumSignAwareArtifactCleaner {
            coordinator.isRunning == false
        }
        let logout = LogoutCoordinator(
            accountStore: accountStore,
            artifactCleaner: cleaner,
            beginWriteInvalidation: {
                coordinator.establishInvalidationBarrier()
                await coordinator.drainInvalidatedOperations()
            },
            endWriteInvalidation: {
                coordinator.endInvalidation()
            }
        )
        let run = Task { @MainActor in
            await coordinator.signAllFollowedForums(account: account)
        }
        try await Task.sleep(for: .milliseconds(100))

        try await logout.logOut()
        let summary = await run.value

        XCTAssertEqual(summary.signedCount, 1)
        XCTAssertTrue(cleaner.observedNoActiveSignRun)
        let storedAccount = try await accountStore.load()
        XCTAssertNil(storedAccount)
        XCTAssertFalse(settings.hasRunToday(accountID: account.id))
        XCTAssertTrue(coordinator.isInvalidating(session: account.sessionIdentity))
        coordinator.endInvalidation()
    }
}

@MainActor
private final class ForumSignAwareArtifactCleaner: SessionArtifactCleaning {
    private let hasNoActiveSignRun: () -> Bool
    private(set) var observedNoActiveSignRun = false

    init(hasNoActiveSignRun: @escaping () -> Bool) {
        self.hasNoActiveSignRun = hasNoActiveSignRun
    }

    func clear() async throws {
        observedNoActiveSignRun = hasNoActiveSignRun()
    }
}
