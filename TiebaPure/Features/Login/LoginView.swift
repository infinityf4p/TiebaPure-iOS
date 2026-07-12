import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var errorMessage: String?
    @State private var isValidating = false
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            LoginWebView { cookies in
                validationTask?.cancel()
                validationTask = Task {
                    await validate(cookies)
                }
            } onError: { error in
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
        isValidating = true
        defer { isValidating = false }

        do {
            let account = try await environment.api.validateLogin(cookies: cookies)
            try Task.checkCancellation()
            try await environment.accountStore.save(account)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = ReaderErrorMessage.message(for: error)
        }
    }
}
