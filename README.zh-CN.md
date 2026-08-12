# Private Signer for iOS

[English](README.md) · **简体中文**

一个供 iOS/iPadOS 使用的 [Private IPA Signer](https://github.com/nnnmdzz/private-signer) Swift 客户端。
v3 契约把项目、源版本和签名 Profile 的权威状态全部放到 Worker。

## v3 契约

项目型 App 只编译一个稳定的 `projectID`。App **不再**自行查 GitHub Release、不携带 unsigned IPA URL、
也不硬编码 provisioning profile ID。Worker 返回当前 `ProjectVersion` 和该 Principal 可使用的 Profile，SDK
只请求签这个不可变版本。

任意 URL/本地 IPA 签名仍保留，但属于另一种能力；Principal 必须明确拥有 `generic-url-sign` 或
`upload-sign` scope。

## 三个产物

| 产物 | 提供什么 |
| --- | --- |
| `PrivateSignerKit` | v3 配置、项目/版本/Profile 发现、项目签名与通用签名 Job、delivery links、OTA URL。 |
| `PrivateSignerSelfUpdate` | Worker 驱动的 `SelfUpdateCoordinator`、当前 ProjectVersion 续签、已安装签名检查。 |
| `PrivateSignerUI` | SwiftUI 配置、自更新、Profile Picker，以及可选的通用 IPA 签名界面。 |

## 安装

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.3.0")
```

请锁精确版本。`0.3.0` 是破坏性的 bug 修复版本，只支持 v3 Worker。

## 最小项目自更新

```swift
import PrivateSignerKit
import PrivateSignerSelfUpdate

let store = SignerConfigurationStore(
    keychain: SignerKeychainConfiguration(
        service: "com.example.app.private-signer",
        configurationAccessGroup: "TEAMID.com.example.app"
    )
)

let coordinator = SelfUpdateCoordinator(
    store: store,
    projectID: "my-app",
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)"
)

if let candidate = try await coordinator.checkForUpdate() {
    let profiles = try await coordinator.availableProfiles()
    let profileID = profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
    var result = try await coordinator.requestSignedBuild(of: candidate, profileID: profileID)
    while result.job.isActive {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        result = try await coordinator.refresh(jobID: result.job.jobID)
    }
    if let installURL = result.installationURL {
        await UIApplication.shared.open(installURL)
    }
}
```

这个流程里 unsigned IPA URL 不会进入 SDK。

## 文档

- [接入指南](docs/client-integration-guide.zh-CN.md) · [English](docs/client-integration-guide.md)
- [API 参考](docs/api-reference.zh-CN.md) · [English](docs/api-reference.md)
- [v3 契约说明](docs/v3-contract.zh-CN.md) · [English](docs/v3-contract.md)

## v3 已删除的旧假设

`/v2`、`GitHubReleaseSource`、`ReleaseSource`、`SignerUIContext.defaultProfileID` 以及具有特殊意义的
`personal-main` 都不再属于本版本。

CI 会编译包并运行单元测试；真机安装/升级仍是最终验收关卡。
