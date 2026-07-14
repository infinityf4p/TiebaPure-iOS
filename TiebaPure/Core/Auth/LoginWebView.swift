import SwiftUI
import UIKit
import WebKit

enum LoginDiagnostics {
#if DEBUG
    private static let prefix = "[TiebaPure.Login]"
#endif

    static func record(_ event: @autoclosure () -> String) {
#if DEBUG
        // DEBUG diagnostics intentionally never record URL queries,
        // fragments, cookie values, account identifiers, phone numbers, or
        // server response bodies. Release builds emit no login diagnostics.
        print("\(prefix) \(event())")
#endif
    }

    static func urlSummary(_ url: URL?) -> String {
        guard let url else { return "url=missing" }
        let scheme = url.scheme?.lowercased() ?? "missing"
        let host = url.host?.lowercased() ?? "none"
        let rawPath = url.path.isEmpty ? "/" : url.path
        let path = String(rawPath.prefix(160))
        return "scheme=\(scheme) host=\(host) path=\(path)"
    }

    static func cookieSummary(_ cookies: [HTTPCookie]) -> String {
        let allowedNames = Set(["BDUSS", "BDUSS_BFESS", "STOKEN", "BAIDUID"])
        let topology = cookies.compactMap { cookie -> String? in
            let name = cookie.name.uppercased()
            guard allowedNames.contains(name) else { return nil }
            let domain = cookie.domain.lowercased()
            let isExpired = cookie.expiresDate.map { $0 <= Date() } ?? false
            return "\(name)@\(domain):secure=\(cookie.isSecure):expired=\(isExpired)"
        }
        return "trustedPrimary=\(AuthSession.hasPrimaryLoginCookie(cookies)) "
            + "trustedRequired=\(AuthSession.hasRequiredCookies(cookies)) "
            + "allowedCookies=[\(topology.joined(separator: ","))]"
    }

    static func navigationType(_ type: WKNavigationType) -> String {
        switch type {
        case .linkActivated: return "link"
        case .formSubmitted: return "formSubmitted"
        case .backForward: return "backForward"
        case .reload: return "reload"
        case .formResubmitted: return "formResubmitted"
        case .other: return "other"
        @unknown default: return "unknown"
        }
    }
}

struct LoginWebView: UIViewRepresentable {
    var onCookiesReady: (BaiduCookies) -> Void
    var onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesReady: onCookiesReady, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        context.coordinator.configureExternalNavigationGuard(in: configuration)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        LoginDiagnostics.record("webViewCreated nonPersistent=true")
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_LOGIN_REDIRECT_FIXTURE") {
            LoginDiagnostics.record("loadingFixture")
            context.coordinator.loadLoginRedirectFixture(in: webView)
        } else {
            LoginDiagnostics.record("loadingLoginURL \(LoginDiagnostics.urlSummary(AuthSession.loginURL))")
            webView.load(URLRequest(url: AuthSession.loginURL))
        }
#else
        LoginDiagnostics.record("loadingLoginURL \(LoginDiagnostics.urlSummary(AuthSession.loginURL))")
        webView.load(URLRequest(url: AuthSession.loginURL))
#endif
        context.coordinator.startCookiePolling(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel(uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let onCookiesReady: (BaiduCookies) -> Void
        private let onError: (Error) -> Void
        private var didComplete = false
        private var isExtractingCookies = false
        private var isCheckingBlockedNavigation = false
        private var isRecoveringPostLogin = false
        private var didAuthorizeCookieValidation = false
        private var didReportMissingCookies = false
        private var cookieValidationDeadline: Date?
        private var approvedCompletionURL: URL?
        private weak var observedWebView: WKWebView?
        private var cookiePollTimer: Timer?

        private static let cookieValidationTimeout: TimeInterval = 30
        private static let blockedNavigationCookieRetryCount = 8
        private static let blockedNavigationCookieRetryDelay: TimeInterval = 0.25
        private static let externalNavigationMessageName = "tiebaPureLoginExternalNavigation"
        private static let externalNavigationGuardSource = """
        (() => {
          if (window.__tiebaPureExternalNavigationGuard) return;
          window.__tiebaPureExternalNavigationGuard = true;

          const notify = () => {
            try {
              window.webkit.messageHandlers.tiebaPureLoginExternalNavigation.postMessage("blocked");
            } catch (_) {}
          };
          const shouldBlock = (rawURL) => {
            if (rawURL === undefined || rawURL === null || rawURL === "") return false;
            let parsed;
            try {
              parsed = new URL(String(rawURL), document.baseURI);
            } catch (_) {
              return true;
            }
            const protocol = parsed.protocol.toLowerCase();
            const host = parsed.hostname.toLowerCase();
            const text = parsed.href.toLowerCase();
            if (!["https:", "http:", "about:"].includes(protocol)) return true;
            if (["apps.apple.com", "itunes.apple.com", "appsto.re"].includes(host)) return true;
            return [
              "tbclient://", "bdtb://", "baidutieba://", "tieba://",
              "baiduboxapp://", "com.baidu.tieba", "id477927812"
            ].some((marker) => text.includes(marker));
          };

          const originalOpen = window.open.bind(window);
          const guardedOpen = (url, target, features) => {
            if (shouldBlock(url)) {
              notify();
              return null;
            }
            return originalOpen(url, target, features);
          };
          try {
            Object.defineProperty(window, "open", {
              value: guardedOpen,
              writable: false,
              configurable: false
            });
          } catch (_) {
            window.open = guardedOpen;
          }

          document.addEventListener("click", (event) => {
            const path = event.composedPath ? event.composedPath() : [event.target];
            const anchor = path.find((node) => node instanceof HTMLAnchorElement && node.href);
            if (anchor && shouldBlock(anchor.href)) {
              event.preventDefault();
              event.stopImmediatePropagation();
              notify();
            }
          }, true);

          document.addEventListener("submit", (event) => {
            const form = event.target;
            if (form instanceof HTMLFormElement && shouldBlock(form.action)) {
              event.preventDefault();
              event.stopImmediatePropagation();
              notify();
            }
          }, true);
        })();
        """

        init(onCookiesReady: @escaping (BaiduCookies) -> Void, onError: @escaping (Error) -> Void) {
            self.onCookiesReady = onCookiesReady
            self.onError = onError
        }

        deinit {
            stopCookiePolling()
        }

        func configureExternalNavigationGuard(in configuration: WKWebViewConfiguration) {
            let controller = configuration.userContentController
            controller.add(self, name: Self.externalNavigationMessageName)
            controller.addUserScript(WKUserScript(
                source: Self.externalNavigationGuardSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        func startCookiePolling(_ webView: WKWebView) {
            observedWebView = webView
            stopCookiePolling()

            let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
                self?.completeIfCookieValidationAllowed()
            }
            cookiePollTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        func stopCookiePolling() {
            cookiePollTimer?.invalidate()
            cookiePollTimer = nil
        }

        func cancel(_ webView: WKWebView) {
            LoginDiagnostics.record("webViewCancelled completed=\(didComplete)")
            didComplete = true
            isExtractingCookies = false
            isCheckingBlockedNavigation = false
            stopCookiePolling()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: Self.externalNavigationMessageName
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.externalNavigationMessageName,
                  didComplete == false,
                  let webView = message.webView ?? observedWebView,
                  let blockedURL = URL(string: "tbclient://blocked-login-redirect") else {
                return
            }
            LoginDiagnostics.record("pageScriptBlockedExternalNavigation")
            handleBlockedNavigation(blockedURL, in: webView, isUserInitiated: true)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                LoginDiagnostics.record("navigationCancelled reason=missingURL")
                decisionHandler(.cancel)
                return
            }

            let target = navigationAction.targetFrame == nil
                ? "newWindow"
                : (navigationAction.targetFrame?.isMainFrame == true ? "main" : "subframe")
            LoginDiagnostics.record(
                "navigation type=\(LoginDiagnostics.navigationType(navigationAction.navigationType)) "
                    + "target=\(target) \(LoginDiagnostics.urlSummary(url)) "
                    + "external=\(AuthSession.isExternalAppRedirectURL(url)) "
                    + "allowed=\(AuthSession.isAllowedLoginURL(url)) "
                    + "success=\(AuthSession.isSuccessURL(url))"
            )

            if AuthSession.isInertLoginDocumentURL(url) {
                LoginDiagnostics.record("navigationAllowed reason=inertDocument")
                decisionHandler(.allow)
                return
            }

            if AuthSession.shouldCaptureCompletionWithoutRendering(url) {
                LoginDiagnostics.record("navigationBlocked reason=captureCompletionWithoutRendering")
                decisionHandler(.cancel)
                captureApprovedCompletion(url, in: webView)
                return
            }

            if AuthSession.isExternalAppRedirectURL(url) {
                LoginDiagnostics.record("navigationBlocked reason=externalAppRedirect")
                decisionHandler(.cancel)
                handleBlockedNavigation(
                    url,
                    in: webView,
                    isUserInitiated: navigationAction.navigationType == .linkActivated
                )
                return
            }

            guard AuthSession.isAllowedLoginURL(url) else {
                LoginDiagnostics.record("navigationBlocked reason=outsideBaiduHTTPSBoundary")
                decisionHandler(.cancel)
                handleBlockedNavigation(
                    url,
                    in: webView,
                    isUserInitiated: navigationAction.navigationType == .linkActivated
                )
                return
            }

            LoginDiagnostics.record("navigationAllowed reason=trustedBaiduHTTPS")
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else {
                LoginDiagnostics.record("newWindowIgnored reason=hasTargetFrame")
                return nil
            }
            guard let url = navigationAction.request.url else {
                LoginDiagnostics.record("newWindowBlocked reason=missingURL")
                return nil
            }

            LoginDiagnostics.record(
                "newWindowIntercepted type=\(LoginDiagnostics.navigationType(navigationAction.navigationType)) "
                    + "\(LoginDiagnostics.urlSummary(url))"
            )

            if AuthSession.isInertLoginDocumentURL(url) {
                LoginDiagnostics.record("newWindowLoadedInPlace reason=inertDocument")
                webView.load(navigationAction.request)
                return nil
            }

            if AuthSession.shouldCaptureCompletionWithoutRendering(url) {
                LoginDiagnostics.record("newWindowBlocked reason=captureCompletionWithoutRendering")
                captureApprovedCompletion(url, in: webView)
                return nil
            }

            if AuthSession.isExternalAppRedirectURL(url) || AuthSession.isAllowedLoginURL(url) == false {
                LoginDiagnostics.record("newWindowBlocked reason=unsafeOrExternal")
                handleBlockedNavigation(
                    url,
                    in: webView,
                    isUserInitiated: navigationAction.navigationType == .linkActivated
                )
                return nil
            }

            LoginDiagnostics.record("newWindowLoadedInPlace reason=trustedBaiduHTTPS")
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else {
                LoginDiagnostics.record("navigationFinished url=missing")
                return
            }

            LoginDiagnostics.record("navigationFinished \(LoginDiagnostics.urlSummary(url))")

            guard AuthSession.isSuccessURL(url) else { return }
            captureApprovedCompletion(url, in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportErrorUnlessIgnorable(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportErrorUnlessIgnorable(error)
        }

        private func completeIfPossible(from webView: WKWebView, reportMissingCookies: Bool) {
            guard didComplete == false, isExtractingCookies == false else {
                return
            }

            isExtractingCookies = true
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                LoginDiagnostics.record("cookieExtractionRequested \(LoginDiagnostics.cookieSummary(cookies))")
                guard let self else { return }
                self.complete(
                    with: self.cookiesReadyForExtraction(cookies),
                    reportMissingCookies: reportMissingCookies
                )
            }
        }

        private func completeIfCookieValidationAllowed() {
            guard let webView = observedWebView,
                  didComplete == false,
                  didAuthorizeCookieValidation,
                  isExtractingCookies == false else {
                return
            }

            isExtractingCookies = true
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let extractionCookies = self.cookiesReadyForExtraction(cookies)
                let shouldValidate = AuthSession.hasRequiredCookies(extractionCookies)

                LoginDiagnostics.record("cookiePoll \(LoginDiagnostics.cookieSummary(cookies))")

                guard shouldValidate else {
                    DispatchQueue.main.async {
                        self.isExtractingCookies = false
                        self.reportMissingCookiesIfTimedOut()
                    }
                    return
                }

                self.complete(with: extractionCookies, reportMissingCookies: false)
            }
        }

        private func handleBlockedNavigation(
            _ url: URL,
            in webView: WKWebView,
            isUserInitiated: Bool
        ) {
            guard didComplete == false, isCheckingBlockedNavigation == false else {
                LoginDiagnostics.record("blockedNavigationCheckSkipped busyOrCompleted=true")
                return
            }

            LoginDiagnostics.record(
                "blockedNavigationCheckStarted userInitiated=\(isUserInitiated) "
                    + LoginDiagnostics.urlSummary(url)
            )
            isCheckingBlockedNavigation = true
            checkBlockedNavigation(
                url,
                in: webView,
                isUserInitiated: isUserInitiated,
                remainingCookieChecks: Self.blockedNavigationCookieRetryCount
            )
        }

        private func checkBlockedNavigation(
            _ url: URL,
            in webView: WKWebView,
            isUserInitiated: Bool,
            remainingCookieChecks: Int
        ) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self, weak webView] cookies in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.didComplete == false, let webView else {
                        self.isCheckingBlockedNavigation = false
                        return
                    }

                    let extractionCookies = self.cookiesReadyForExtraction(cookies)
                    let hasPrimaryLoginCookie = AuthSession.hasPrimaryLoginCookie(extractionCookies)
                    LoginDiagnostics.record(
                        "blockedNavigationCookieCheck remaining=\(remainingCookieChecks) "
                            + LoginDiagnostics.cookieSummary(cookies)
                    )
                    if hasPrimaryLoginCookie == false, remainingCookieChecks > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.blockedNavigationCookieRetryDelay) {
                            self.checkBlockedNavigation(
                                url,
                                in: webView,
                                isUserInitiated: isUserInitiated,
                                remainingCookieChecks: remainingCookieChecks - 1
                            )
                        }
                        return
                    }

                    self.isCheckingBlockedNavigation = false

                    let resolution = AuthSession.blockedNavigationResolution(
                        for: url,
                        hasPrimaryLoginCookie: hasPrimaryLoginCookie,
                        isUserInitiated: isUserInitiated
                    )
                    switch resolution {
                    case .recoverOnTiebaWeb:
                        LoginDiagnostics.record("blockedNavigationResolved action=recoverOnTiebaWeb")
                        self.recoverPostLogin(in: webView)
                    case .ignore:
                        LoginDiagnostics.record("blockedNavigationResolved action=ignore")
                        break
                    case .reportError:
                        LoginDiagnostics.record("blockedNavigationResolved action=reportError")
                        self.onError(AuthSessionError.disallowedNavigation)
                    }
                }
            }
        }

        private func recoverPostLogin(in webView: WKWebView) {
            guard isRecoveringPostLogin == false else {
                LoginDiagnostics.record("postLoginRecoverySkipped alreadyRecovering=true")
                return
            }
            isRecoveringPostLogin = true
            LoginDiagnostics.record(
                "postLoginRecoveryLoading \(LoginDiagnostics.urlSummary(AuthSession.loginCompletionURL))"
            )
            var request = URLRequest(
                url: AuthSession.loginCompletionURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            request.httpShouldHandleCookies = true
            // Cookie validation is authorized only when WKWebView asks the
            // navigation delegate to allow this exact HTTPS completion URL.
            webView.load(request)
        }

        private func captureApprovedCompletion(_ completionURL: URL, in webView: WKWebView) {
            authorizeCookieValidation(for: completionURL)
            // Do not render the Universal Link claimed by the official Tieba
            // app. Replacing the document also terminates any login-page
            // script that might attempt a second app handoff.
            webView.stopLoading()
            webView.loadHTMLString(
                "<!doctype html><html lang=\"zh-CN\"><meta name=\"viewport\" content=\"width=device-width\"><body></body></html>",
                baseURL: nil
            )
            completeIfPossible(from: webView, reportMissingCookies: false)
        }

        private func authorizeCookieValidation(for completionURL: URL) {
            guard AuthSession.isSuccessURL(completionURL) else {
                LoginDiagnostics.record("cookieValidationAuthorizationRejected reason=untrustedCompletionURL")
                return
            }
            guard didAuthorizeCookieValidation == false else {
                LoginDiagnostics.record("cookieValidationAlreadyAuthorized")
                return
            }
            approvedCompletionURL = completionURL
            didAuthorizeCookieValidation = true
            cookieValidationDeadline = Date().addingTimeInterval(Self.cookieValidationTimeout)
            LoginDiagnostics.record("cookieValidationAuthorized timeoutSeconds=30")
        }

        private func cookiesReadyForExtraction(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
            guard let approvedCompletionURL else { return cookies }
            let normalized = AuthSession.cookiesForApprovedHTTPSCompletion(
                cookies,
                completionURL: approvedCompletionURL
            )
            let didUpgrade = zip(cookies, normalized).contains { original, candidate in
                original.isSecure == false && candidate.isSecure
            }
            if didUpgrade {
                LoginDiagnostics.record("approvedHTTPSCookieCompatibilityUpgradeApplied")
            }
            return normalized
        }

        private func reportMissingCookiesIfTimedOut() {
            guard didComplete == false,
                  didAuthorizeCookieValidation,
                  didReportMissingCookies == false,
                  let cookieValidationDeadline,
                  Date() >= cookieValidationDeadline else {
                return
            }
            didReportMissingCookies = true
            LoginDiagnostics.record("cookieValidationFailed reason=missingRequiredCookiesTimeout")
            onError(AuthSessionError.missingRequiredCookies)
        }

        private func complete(with cookies: [HTTPCookie], reportMissingCookies: Bool) {
            do {
                let result = try AuthSession.extract(from: cookies)
                DispatchQueue.main.async {
                    guard self.didComplete == false else { return }
                    LoginDiagnostics.record("cookieExtractionSucceeded")
                    self.didComplete = true
                    self.isExtractingCookies = false
                    self.stopCookiePolling()
                    self.onCookiesReady(result)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExtractingCookies = false
                    LoginDiagnostics.record(
                        "cookieExtractionNotReady errorType=\(String(reflecting: type(of: error)))"
                    )
                    guard reportMissingCookies else { return }
                    self.onError(error)
                }
            }
        }

        private func reportErrorUnlessIgnorable(_ error: Error) {
            guard didComplete == false, isIgnorableNavigationError(error) == false else {
                let nsError = error as NSError
                LoginDiagnostics.record(
                    "navigationErrorIgnored domain=\(nsError.domain) code=\(nsError.code)"
                )
                return
            }
            let nsError = error as NSError
            LoginDiagnostics.record("navigationErrorReported domain=\(nsError.domain) code=\(nsError.code)")
            DispatchQueue.main.async {
                self.onError(error)
            }
        }

        private func isIgnorableNavigationError(_ error: Error) -> Bool {
            let nsError = error as NSError
            guard nsError.domain == NSURLErrorDomain else { return false }
            return nsError.code == NSURLErrorCancelled || nsError.code == NSURLErrorUnsupportedURL
        }

#if DEBUG
        func loadLoginRedirectFixture(in webView: WKWebView) {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let properties: [[HTTPCookiePropertyKey: Any]] = [
                [
                    .name: "BDUSS",
                    .value: "fixture-bduss",
                    .domain: ".baidu.com",
                    .path: "/",
                    .secure: "TRUE"
                ],
                [
                    .name: "STOKEN",
                    .value: "fixture-stoken",
                    .domain: ".tieba.baidu.com",
                    .path: "/",
                    .secure: "TRUE"
                ]
            ]
            let cookies = properties.compactMap(HTTPCookie.init(properties:))

            func installCookie(at index: Int) {
                guard index < cookies.count else {
                    let html = """
                    <!doctype html>
                    <html lang="zh-CN">
                    <head>
                      <meta name="viewport" content="width=device-width, initial-scale=1">
                      <style>
                        body { font: -apple-system-body; padding: 32px 20px; }
                        a { display: block; padding: 18px; text-align: center; }
                      </style>
                    </head>
                    <body>
                      <h1>验证码验证完成</h1>
                      <a aria-label="跳过设置密码" href="#" onclick="window.open('https://a.app.qq.com/o/simple.jsp?pkgname=com.baidu.tieba', '_blank'); return false;">
                        跳过设置密码
                      </a>
                    </body>
                    </html>
                    """
                    webView.loadHTMLString(html, baseURL: URL(string: "https://wappass.baidu.com/passport")!)
                    return
                }
                cookieStore.setCookie(cookies[index]) {
                    installCookie(at: index + 1)
                }
            }
            installCookie(at: 0)
        }
#endif
    }
}
