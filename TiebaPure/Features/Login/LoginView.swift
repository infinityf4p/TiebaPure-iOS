import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var errorMessage: String?
    @State private var isValidating = false
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            LoginWebView { cookies in
                LoginDiagnostics.record("cookiesReady validationTaskStarting")
                validationTask?.cancel()
                validationTask = Task {
                    await validate(cookies)
                }
            } onError: { error in
                LoginDiagnostics.record(
                    "loginViewError errorType=\(String(reflecting: type(of: error)))"
                )
                errorMessage = ReaderErrorMessage.message(for: error)
            }

            if isValidating {
                ProgressView()
                    .controlSize(.large)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card))
                    .accessibilityLabel("正在验证登录")
            }
        }
        .ignoresSafeArea(.keyboard)
        .alert("登录失败", isPresented: isShowingError) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            LoginDiagnostics.record("loginViewDisappeared validationTaskCancelled=true")
            validationTask?.cancel()
            validationTask = nil
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            errorMessage != nil
        } set: { isShowing in
            if isShowing == false {
                errorMessage = nil
            }
        }
    }

    @MainActor
    private func validate(_ cookies: BaiduCookies) async {
        LoginDiagnostics.record("apiValidationStarted")
        isValidating = true
        defer { isValidating = false }

        do {
            let account = try await environment.api.validateLogin(cookies: cookies)
            LoginDiagnostics.record("apiValidationSucceeded accountStoreSaveStarting")
            try Task.checkCancellation()
            try await environment.accountStore.save(account)
            LoginDiagnostics.record("accountStoreSaveSucceeded")
        } catch is CancellationError {
            LoginDiagnostics.record("apiValidationCancelled")
            return
        } catch {
            LoginDiagnostics.record(
                "apiValidationFailed errorType=\(String(reflecting: type(of: error)))"
            )
            errorMessage = ReaderErrorMessage.message(for: error)
        }
    }
}
