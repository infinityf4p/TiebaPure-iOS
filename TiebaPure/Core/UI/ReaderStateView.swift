import SwiftUI
import UIKit

struct InlineLoadErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TiebaPureTheme.Spacing.xs)
            Button("重试", action: retry)
                .buttonStyle(.bordered)
                .minTouchTarget()
                .accessibilityHint("重新执行刚才失败的请求")
        }
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(TiebaPureTheme.ColorToken.readerSecondarySurface)
        .accessibilityElement(children: .contain)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

struct ReaderStateView: View {
    enum Kind {
        case loading
        case empty
        case error
        case expiredSession
    }

    let kind: Kind
    let title: String
    let message: String?
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        kind: Kind,
        title: String,
        message: String? = nil,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: TiebaPureTheme.Spacing.sm) {
            switch kind {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel(title)
            case .empty, .error, .expiredSession:
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, TiebaPureTheme.Spacing.xs)
                    .minTouchTarget()
            }
        }
        .padding(TiebaPureTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Gives empty and error states a real vertical scroll container so an
/// ancestor's `.refreshable` action remains reachable even when there is no
/// list content yet.
struct ReaderStateScrollView<Content: View>: View {
    private let refresh: () async -> Void
    private let content: Content

    init(
        refresh: @escaping () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.refresh = refresh
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    // Keep the empty state genuinely scrollable. A content
                    // height exactly equal to the viewport intermittently
                    // suppresses UIRefreshControl on iOS 26.1.
                    .frame(minHeight: max(proxy.size.height + 1, 1))
            }
            .refreshable { await refresh() }
            .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
            .accessibilityIdentifier("reader-state-scroll-view")
        }
    }
}

extension ReaderStateView {
    static func loading(_ title: String = "正在加载") -> ReaderStateView {
        ReaderStateView(kind: .loading, title: title, systemImage: "hourglass")
    }

    static func empty(
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> ReaderStateView {
        ReaderStateView(
            kind: .empty,
            title: title,
            message: message,
            systemImage: "tray",
            actionTitle: actionTitle,
            action: action
        )
    }

    static func error(
        title: String = "加载失败",
        message: String? = nil,
        actionTitle: String? = "重试",
        action: (() -> Void)? = nil
    ) -> ReaderStateView {
        ReaderStateView(
            kind: .error,
            title: title,
            message: message,
            systemImage: "exclamationmark.triangle",
            actionTitle: actionTitle,
            action: action
        )
    }

    static func expiredSession(action: (() -> Void)? = nil) -> ReaderStateView {
        ReaderStateView(
            kind: .expiredSession,
            title: "登录已失效",
            message: "请重新登录后查看关注的贴吧。",
            systemImage: "person.crop.circle.badge.exclamationmark",
            actionTitle: "重新登录",
            action: action
        )
    }
}

enum ReaderErrorMessage {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "请求超时，请稍后重试。"
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return "网络不可用，请检查网络连接。"
            case .cancelled:
                return "请求已取消。"
            default:
                return "网络请求失败，请稍后重试。"
            }
        }

        if error is DecodingError {
            return "数据解析失败，请刷新后重试。"
        }

        if let authError = error as? AuthSessionError {
            switch authError {
            case .missingRequiredCookies:
                return "登录凭证不完整，请返回登录页重试。"
            case .untrustedCookie:
                return "登录凭证未通过安全校验，请重新登录。"
            case .disallowedNavigation:
                return "已阻止不安全的登录页面跳转。"
            }
        }

        if let loginError = error as? LoginValidationError {
            return loginError.description
        }

        if error is KeychainError || error is AccountMigrationError || error is AccountStoreError {
            return "本机账号数据处理失败，请重新登录或稍后重试。"
        }

        if error is TiebaRequestValidationError {
            return "请求参数无效，无法继续加载。"
        }

        if case let TiebaHTTPError.badStatus(code, _) = error {
            return code == 401 || code == 403
                ? "当前请求未获授权，请重新登录或稍后重试。"
                : "服务器暂时不可用（\(code)），请稍后重试。"
        }

        if case .responseTooLarge = error as? TiebaHTTPError {
            return "响应内容超过安全大小限制。"
        }

        if case .sessionExpired = error as? TiebaAPIError {
            return "登录已失效，请重新登录。"
        }

        if let apiError = error as? TiebaAPIError,
           case let .response(_, message) = apiError,
           message.isEmpty == false {
            return message
        }

        return "加载失败，请稍后重试。"
    }
}
