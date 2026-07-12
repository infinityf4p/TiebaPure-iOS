import SwiftUI
import UIKit
import WebKit

struct LoginWebView: UIViewRepresentable {
    var onCookiesReady: (BaiduCookies) -> Void
    var onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesReady: onCookiesReady, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: AuthSession.loginURL))
        context.coordinator.startCookiePolling(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel(uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCookiesReady: (BaiduCookies) -> Void
        private let onError: (Error) -> Void
        private var didComplete = false
        private var isExtractingCookies = false
        private weak var observedWebView: WKWebView?
        private var cookiePollTimer: Timer?

        init(onCookiesReady: @escaping (BaiduCookies) -> Void, onError: @escaping (Error) -> Void) {
            self.onCookiesReady = onCookiesReady
            self.onError = onError
        }

        deinit {
            stopCookiePolling()
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
            didComplete = true
            isExtractingCookies = false
            stopCookiePolling()
            webView.stopLoading()
            webView.navigationDelegate = nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if AuthSession.isExternalAppRedirectURL(url) {
                decisionHandler(.cancel)
                return
            }

            guard AuthSession.isAllowedLoginURL(url) else {
                decisionHandler(.cancel)
                if let safeURL = TiebaURL.webpage(url.absoluteString) {
                    UIApplication.shared.open(safeURL)
                } else {
                    onError(AuthSessionError.disallowedNavigation)
                }
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else {
                return
            }

            guard AuthSession.isSuccessURL(url) else { return }
            completeIfPossible(from: webView, reportMissingCookies: true)
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
                self?.complete(with: cookies, reportMissingCookies: reportMissingCookies)
            }
        }

        private func completeIfCookieValidationAllowed() {
            guard let webView = observedWebView,
                  didComplete == false,
                  isExtractingCookies == false else {
                return
            }

            isExtractingCookies = true
            let currentURL = webView.url
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let shouldValidate = currentURL.map(AuthSession.shouldAttemptCookieValidation(on:)) == true
                    && AuthSession.hasRequiredCookies(cookies)

                guard shouldValidate else {
                    DispatchQueue.main.async {
                        self.isExtractingCookies = false
                    }
                    return
                }

                self.complete(with: cookies, reportMissingCookies: false)
            }
        }

        private func complete(with cookies: [HTTPCookie], reportMissingCookies: Bool) {
            do {
                let result = try AuthSession.extract(from: cookies)
                DispatchQueue.main.async {
                    guard self.didComplete == false else { return }
                    self.didComplete = true
                    self.isExtractingCookies = false
                    self.stopCookiePolling()
                    self.onCookiesReady(result)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExtractingCookies = false
                    guard reportMissingCookies else { return }
                    self.onError(error)
                }
            }
        }

        private func reportErrorUnlessIgnorable(_ error: Error) {
            guard didComplete == false, isIgnorableNavigationError(error) == false else {
                return
            }
            DispatchQueue.main.async {
                self.onError(error)
            }
        }

        private func isIgnorableNavigationError(_ error: Error) -> Bool {
            let nsError = error as NSError
            guard nsError.domain == NSURLErrorDomain else { return false }
            return nsError.code == NSURLErrorCancelled || nsError.code == NSURLErrorUnsupportedURL
        }
    }
}
