import SwiftUI

struct MeView: View {
    let account: Account?

    @State private var showsLogin = false
    @State private var showsFollowedForums = false

    var body: some View {
        NavigationStack {
            Form {
                if let account {
                    Section("账号") {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            AvatarView(
                                url: account.portraitURL,
                                title: account.displayName,
                                size: TiebaPureTheme.AvatarSize.large
                            )

                            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                                Text(account.displayName)
                                    .font(.body.weight(.semibold))

                                Text("UID \(account.uid)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, TiebaPureTheme.Spacing.xs)

                        ZStack(alignment: .leading) {
                            Label("我的关注吧", systemImage: "star")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .overlay {
                            Button {
                                showsFollowedForums = true
                            } label: {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityLabel("我的关注吧")
                            .accessibilityHint("打开已关注的贴吧列表")
                        }

                        NavigationLink {
                            SettingsView(account: account)
                        } label: {
                            Label("设置", systemImage: "gearshape")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                } else {
                    Section("账号") {
                        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                            Label("未登录也可以浏览公开帖子", systemImage: "book")
                                .font(.body)

                            Button {
                                showsLogin = true
                            } label: {
                                Label("手机号验证码登录", systemImage: "iphone.gen2")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityHint("打开百度移动登录页，使用手机号和验证码登录。")
                        }
                        .padding(.vertical, TiebaPureTheme.Spacing.xs)
                    }
                }

                Section("应用") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于 TiebaPure", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("查看来源、许可证和源码链接")
                }
            }
            .navigationTitle("我的")
            .navigationDestination(isPresented: $showsFollowedForums) {
                if let account {
                    ForumListView(account: account)
                }
            }
            .sheet(isPresented: $showsLogin) {
                NavigationStack {
                    LoginView()
                        .navigationTitle("手机号验证码登录")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("关闭") {
                                    showsLogin = false
                                }
                            }
                        }
                }
            }
            .onChange(of: account?.id) { newValue in
                if newValue != nil {
                    showsLogin = false
                } else {
                    showsFollowedForums = false
                }
            }
        }
    }
}
