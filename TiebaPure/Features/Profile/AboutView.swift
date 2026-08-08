import SwiftUI

struct AboutView: View {
    private let sourceURL = URL(string: "https://github.com/infinityf4p/TiebaPure-iOS")!
    private let authorURL = URL(string: "https://github.com/infinityf4p")!
    private let gplURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    private let swiftProtobufLicenseURL = URL(
        string: "https://github.com/apple/swift-protobuf/blob/1.38.1/LICENSE.txt"
    )!

    var body: some View {
        Form {
            Section("TiebaPure") {
                LabeledContent("版本", value: versionText)
                LabeledContent("项目作者") {
                    Link("infinityf4p", destination: authorURL)
                }
                Text("以浏览为主的非官方百度贴吧客户端；登录后支持关注、点赞，以及实验性的发帖与回复。与百度公司及贴吧官方无隶属、授权或认可关系。")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("开源与许可") {
                Link("查看 TiebaPure-iOS 源码", destination: sourceURL)
                    .accessibilityHint("在浏览器打开本应用源码")

                NavigationLink {
                    OpenSourceLicenseView(
                        title: "TiebaPure-iOS",
                        resourceName: "LICENSE",
                        resourceExtension: nil,
                        fallbackURL: gplURL
                    )
                } label: {
                    LabeledContent("TiebaPure-iOS", value: "GPL-3.0-only")
                }

                NavigationLink {
                    OpenSourceLicenseView(
                        title: "SwiftProtobuf",
                        resourceName: "SwiftProtobuf-Apache-2.0",
                        resourceExtension: "txt",
                        fallbackURL: swiftProtobufLicenseURL
                    )
                } label: {
                    LabeledContent("SwiftProtobuf", value: "Apache-2.0")
                }
            }
        }
        .navigationTitle("关于 TiebaPure")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenInteractiveNavigationPop()
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }
}

private struct OpenSourceLicenseView: View {
    let title: String
    let resourceName: String
    let resourceExtension: String?
    let fallbackURL: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let licenseText {
                ScrollView {
                    Text(verbatim: licenseText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            } else {
                CompatibleContentUnavailableSimple(
                    "无法读取许可证",
                    systemImage: "doc.text",
                    description: "可通过右上角按钮查看官方许可证。"
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    openURL(fallbackURL)
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("在浏览器中查看许可证")
            }
        }
        .fullScreenInteractiveNavigationPop()
    }

    private var licenseText: String? {
        let candidateURLs = [
            Bundle.main.url(forResource: resourceName, withExtension: resourceExtension),
            Bundle.main.url(
                forResource: resourceName,
                withExtension: resourceExtension,
                subdirectory: "LICENSES"
            )
        ]

        for case let url? in candidateURLs {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return nil
    }
}
