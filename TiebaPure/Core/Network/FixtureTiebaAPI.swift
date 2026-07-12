#if DEBUG
import Foundation

enum FixtureScenario: String {
    case success
    case empty
    case error
    case expired
    case slow
    case paginationFailure
    case longContent
}

struct FixtureTiebaAPI: TiebaAPIService {
    let scenario: FixtureScenario
    let delayNanoseconds: UInt64
    private let state: FixtureRequestState

    init(scenario: FixtureScenario = .success, delayMilliseconds: Int = 0) {
        self.scenario = scenario
        delayNanoseconds = UInt64(max(delayMilliseconds, 0)) * 1_000_000
        state = FixtureRequestState()
    }

    func validateLogin(cookies: BaiduCookies) async throws -> Account {
        try await prepare()
        return Self.account
    }

    func personalizedThreads(account: Account?, page: Int, loadType: Int) async throws -> [ThreadSummary] {
        try await prepare(page: page)
        guard scenario != .empty else { return [] }
        return page == 1 ? Self.threads : []
    }

    func followedForums(account: Account) async throws -> [Forum] {
        try await prepare()
        guard scenario != .empty else { return [] }
        return [Self.forum, Self.forumTwo]
    }

    func forumThreads(account: Account?, forumName: String, page: Int, sortType: Int) async throws -> [ThreadSummary] {
        try await prepare(page: page)
        guard scenario != .empty else { return [] }
        return page == 1 ? Self.threads.map { thread in
            var copy = thread
            copy.forumName = forumName
            return copy
        } : []
    }

    func searchThreads(
        keyword: String,
        page: Int,
        sortType: Int,
        filterType: Int,
        forumName: String?,
        pageSize: Int
    ) async throws -> SearchResultsPage {
        if scenario == .slow || keyword == "慢请求" {
            try await Task.sleep(nanoseconds: max(delayNanoseconds, 900_000_000))
        } else {
            try await prepare(page: page)
        }
        guard scenario != .empty else {
            return SearchResultsPage(results: [], currentPage: page, hasMore: false)
        }
        if keyword == "仅回复命中", filterType == 1 {
            return SearchResultsPage(results: [], currentPage: page, hasMore: false)
        }
        let result = SearchResult(
            threadID: 1001,
            postID: 2002,
            forumID: Self.forum.id,
            forumName: forumName ?? Self.forum.name,
            forumAvatarURL: nil,
            title: "\(keyword) 的确定性搜索结果",
            content: "命中第二楼回复，可验证 postID 路由。",
            author: Self.author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            replyCount: 3,
            likeCount: 2,
            shareCount: 1,
            blocks: [],
            isReplyMatch: true
        )
        return SearchResultsPage(results: page == 1 ? [result] : [], currentPage: page, hasMore: false)
    }

    func threadPage(
        account: Account?,
        threadID: Int64,
        page: Int,
        forumID: Int64?,
        postID: UInt64?,
        seeLz: Bool,
        sortType: ThreadReplySort
    ) async throws -> ThreadPage {
        try await prepare(page: page)
        let thread = Self.threads.first(where: { $0.id == threadID }) ?? Self.threads[0]
        let text = scenario == .longContent
            ? String(repeating: "这是用于大字体与超长正文布局验收的合成内容。", count: 80)
            : "这是完全离线的合成帖子正文，内容不来自真实用户。"
        let longImage = ImageContent(
            thumbnailURL: URL(string: "https://fixture.invalid/long-image.png"),
            originalURL: URL(string: "https://fixture.invalid/long-image-original.png"),
            width: 400,
            height: 1_600,
            showOriginalButton: true
        )
        let main = Post(
            id: 2001,
            threadID: threadID,
            floor: 1,
            author: Self.author,
            ipAddress: "北京",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            blocks: [
                .text(text),
                .link(title: "百度贴吧 HTTPS 链接", url: URL(string: "https://tieba.baidu.com")),
                .image(longImage)
            ],
            subpostCount: 0,
            likeCount: 12,
            previewSubposts: []
        )
        let replyAuthor = UserSummary(id: 2, name: "fixture_reply", displayName: "很长很长的合成回复用户名用于布局测试", portrait: "", level: 12, levelName: "十二级")
        let replyText = postID == 2002 ? "已定位搜索命中回复" : "确定性回复内容"
        let reply = Post(
            id: 2002,
            threadID: threadID,
            floor: 2,
            author: replyAuthor,
            ipAddress: "上海",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            blocks: [.text(replyText), .mention(userID: 1, text: "@合成作者")],
            subpostCount: 2,
            likeCount: 3,
            previewSubposts: Self.subpostFixtures
        )
        let posts = page == 1 ? [main, reply] : []
        return ThreadPage(
            thread: thread,
            forum: Self.forum,
            mainPost: main,
            posts: posts,
            currentPage: page,
            totalPage: 1,
            hasMore: false
        )
    }

    func subposts(
        account: Account?,
        threadID: Int64,
        postID: UInt64,
        forumID: Int64,
        page: Int,
        subpostID: UInt64
    ) async throws -> [Subpost] {
        try await prepare(page: page)
        return page == 1 ? Self.subpostFixtures : []
    }

    private func prepare(page: Int = 1) async throws {
        try Task.checkCancellation()
        if delayNanoseconds > 0 || scenario == .slow {
            try await Task.sleep(nanoseconds: max(delayNanoseconds, scenario == .slow ? 900_000_000 : 0))
        }
        try Task.checkCancellation()
        if scenario == .paginationFailure, page > 1, await state.shouldFail(page: page) {
            throw URLError(.timedOut)
        }
        if scenario == .expired { throw TiebaAPIError.sessionExpired(code: 110001, message: "登录已失效") }
        if scenario == .error { throw URLError(.notConnectedToInternet) }
    }

    static let account = Account(
        uid: "fixture-account",
        name: "fixture_user",
        displayName: "模拟登录用户",
        portrait: "",
        bduss: "fixture-bduss",
        stoken: "fixture-stoken",
        baiduID: "fixture-baiduid",
        tbs: "fixture-tbs"
    )

    static let forum = Forum(id: 101, name: "测试", displayName: "测试吧", avatarURL: nil, memberCount: 12345, threadCount: 678)
    static let forumTwo = Forum(id: 102, name: "无障碍", displayName: "无障碍吧", avatarURL: nil, memberCount: 44, threadCount: 88)
    static let author = UserSummary(id: 1, name: "fixture_author", displayName: "合成内容作者", portrait: "", level: 9, levelName: "九级")

    static let threads: [ThreadSummary] = {
        let fourImages = (0..<4).map { index in
            ContentBlock.image(ImageContent(
                thumbnailURL: nil,
                originalURL: nil,
                width: index == 0 ? 400 : 800,
                height: index == 0 ? 1_600 : 600,
                showOriginalButton: index == 0
            ))
        }
        return [
            ThreadSummary(
                id: 1001,
                forumID: forum.id,
                title: "确定性主帖：回复筛选与媒体布局",
                author: author,
                forumName: forum.name,
                replyCount: 3,
                viewCount: 120,
                likeCount: 12,
                blocks: [.text("合成摘要，不含真实贴吧用户内容。")] + fourImages,
                isGood: true
            ),
            ThreadSummary(
                id: 1002,
                forumID: forumTwo.id,
                title: "超长昵称、深色模式和辅助功能字号",
                author: UserSummary(id: 2, name: "long", displayName: "这是一个特别长的合成用户名用于验证自动换行", portrait: "", level: 18, levelName: "十八级"),
                forumName: forumTwo.name,
                replyCount: 0,
                viewCount: 1,
                blocks: [.text("第二条确定性内容")]
            ),
            ThreadSummary(
                id: 1003,
                forumID: forum.id,
                title: "单张超宽图片布局",
                author: author,
                forumName: forum.name,
                replyCount: 1,
                viewCount: 8,
                blocks: [
                    .text("一张合成超宽图"),
                    .image(ImageContent(
                        thumbnailURL: nil,
                        originalURL: nil,
                        width: 2_400,
                        height: 600,
                        showOriginalButton: false
                    ))
                ]
            ),
            ThreadSummary(
                id: 1004,
                forumID: forumTwo.id,
                title: "三张媒体网格布局",
                author: author,
                forumName: forumTwo.name,
                replyCount: 2,
                viewCount: 16,
                blocks: [.text("三张合成媒体")] + (0..<3).map { index in
                    .image(ImageContent(
                        thumbnailURL: nil,
                        originalURL: nil,
                        width: index == 0 ? 600 : 800,
                        height: index == 0 ? 800 : 600,
                        showOriginalButton: false
                    ))
                }
            )
        ]
    }()

    static let subpostFixtures = [
        Subpost(id: 3001, floor: 1, author: author, ipAddress: "广东", blocks: [.text("楼中楼合成回复一")], createdAt: nil, likeCount: 1),
        Subpost(id: 3002, floor: 2, author: author, ipAddress: "浙江", blocks: [.text("楼中楼合成回复二")], createdAt: nil, likeCount: 0)
    ]
}

private actor FixtureRequestState {
    private var failedPages = Set<Int>()

    func shouldFail(page: Int) -> Bool {
        failedPages.insert(page).inserted
    }
}
#endif
