# Tieba Protobuf Inputs

302 source schemas were copied from
[`HuanCheng65/TiebaLite`](https://github.com/HuanCheng65/TiebaLite/tree/4.0-dev/app/src/main/protos)
at `4.0-dev@2885b2aabbbf47aba7bf12b1cd7cbc03b1f5ec15`. They were verified
byte-for-byte when this repository was prepared. The generator reads only this
repository's `Protos/` directory and never requires an external checkout.

`TiebaPureProfile/` is original to this project and is not part of the
TiebaLite-copied set; CI counts the copied schemas excluding that directory.

Only reader-required root schemas are selected for iOS:

- `CommonRequest.proto`
- `AppPosInfo.proto`
- `Personalized.proto`
- `FrsPage/FrsPage.proto`
- `ThreadList/AdParam.proto`
- `ThreadList/ThreadList.proto`
- `PbPage/PbPageRequest.proto`
- `PbPage/PbPageRequestData.proto`
- `PbPage/PbPageResponse.proto`
- `PbPage/PbPageResponseData.proto`
- `PbFloor/PbFloorRequest.proto`
- `PbFloor/PbFloorRequestData.proto`
- `PbFloor/PbFloorResponse.proto`
- `PbFloor/PbFloorResponseData.proto`
- `Post.proto`
- `SubPost.proto`
- `SubPostList.proto`
- `PbContent.proto`
- `ThreadInfo.proto`
- `ForumInfo.proto`
- `SimpleForum.proto`
- `User.proto`
- `Media.proto`
- `VideoInfo.proto`
- `Page.proto`
- `Anti.proto`
- `Error.proto`

If generation fails because an imported schema is missing, update the
repository's audited `Protos/` set in a separately reviewed change; do not
silently read files from another checkout or add unrelated feature endpoints.

The generation script recursively includes the import closure of these roots. That produces shared message types referenced by reader responses, but it does not add write endpoints such as posting, profile editing, or sign-in automation.

Regeneration requires `python3`, `protoc`, and `protoc-gen-swift` 1.38.1. The
Swift generator version is intentionally kept equal to the SwiftProtobuf
package version pinned in `Package.resolved`; the script validates it before
removing or replacing committed generated sources.
