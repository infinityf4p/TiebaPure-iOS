# Tieba Protobuf Inputs

部分贴吧接口使用 Protobuf 传输数据。本目录保存 TiebaPure 自行维护的最小协议定义，只包含应用实际发送或读取的字段；响应中的其他字段由 Protobuf 作为未知字段跳过。

字段编号、wire 类型以及 `optional` / `repeated` 语义都是协议的一部分。修改它们时必须同步增加手写 wire fixture，并验证请求编码、响应解码和领域模型映射，不能仅依赖同一份 schema 的编码再解码测试。

`scripts/generate-ios-protos.sh` 只读取本目录，不依赖外部 checkout。脚本从阅读接口的根 schema 递归解析 import，拒绝未进入生成闭包的孤立文件，并先在临时目录完成生成，成功后才替换已提交的 Swift 产物。

生成需要 `python3`、`protoc` 和 `protoc-gen-swift 1.38.1`。Swift 生成器版本必须与工程使用的 SwiftProtobuf 版本一致，脚本会在覆盖产物前校验。
