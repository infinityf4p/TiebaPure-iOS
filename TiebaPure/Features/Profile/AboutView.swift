import SwiftUI

struct AboutView: View {
    private let upstreamURL = URL(string: "https://github.com/HuanCheng65/TiebaLite/tree/4.0-dev")!
    private let sourceURL = URL(string: "https://github.com/infinityf4p/TiebaPure-iOS")!

    var body: some View {
        Form {
            Section("TiebaPure") {
                LabeledContent("版本", value: versionText)
                Text("非官方百度贴吧只读客户端，与百度公司及贴吧官方无隶属、授权或认可关系。")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("开源与来源") {
                Text("本项目在设计与实现过程中借鉴并移植自 HuanCheng65/TiebaLite 的 4.0-dev 分支，感谢原作者及贡献者。")
                    .fixedSize(horizontal: false, vertical: true)

                Link("查看 TiebaLite 来源项目", destination: upstreamURL)
                    .accessibilityHint("在浏览器打开原项目")

                Link("查看 TiebaPure-iOS 源码", destination: sourceURL)
                    .accessibilityHint("在浏览器打开本应用源码")

                LabeledContent("许可证", value: "GPL-3.0-only")
                Text("本软件不提供任何担保。第三方资源的来源与许可请以仓库中的 THIRD_PARTY_NOTICES.md 和资产清单为准。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("关于 TiebaPure")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version)（\(build)）"
    }
}
