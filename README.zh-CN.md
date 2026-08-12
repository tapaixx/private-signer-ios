# Private Signer for iOS

[English](README.md) · **简体中文**

供 iOS/iPadOS 使用的 [Private IPA Signer](https://github.com/nnnmdzz/private-signer) Swift 客户端。SDK 只维护 **一个服务契约：v2**。

## 契约

项目型 App 只编译稳定的 `projectID`。App 不自行查 GitHub Release、不携带 unsigned IPA URL，也不硬编码 provisioning Profile ID。Worker 维护项目/版本目录和 allowed/default Profile 策略，SDK 只请求签指定的 `ProjectVersion`。

项目发现、Profile 发现、项目签名、通用 URL/upload 签名、Job history 和 delivery link 全部统一使用 `/v2/*`，并使用 App 配置中现有的同一个 `SIGNING_REQUEST_TOKEN`。

不再有第二套客户端 Token。`personal-main` 没有任何特殊意义；Profile ID 全部来自 Worker discovery。

## 三个产物

| 产物 | 提供什么 |
| --- | --- |
| `PrivateSignerKit` | v2 配置、项目/版本/Profile 发现、项目与通用签名 Job、delivery links、OTA URL。 |
| `PrivateSignerSelfUpdate` | Worker 驱动的 `SelfUpdateCoordinator`、当前 ProjectVersion 续签、已安装签名检查。 |
| `PrivateSignerUI` | SwiftUI 配置、自更新、Profile Picker，以及可选的通用 IPA 签名界面。 |

## 安装

App 应固定到已验收的 immutable tag 或 commit；开发阶段优先使用固定 revision，不使用浮动版本范围。

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

这个自更新流程中 unsigned IPA URL 不会进入 SDK。

## 文档

- [接入指南](docs/client-integration-guide.zh-CN.md) · [English](docs/client-integration-guide.md)
- [API 参考](docs/api-reference.zh-CN.md) · [English](docs/api-reference.md)
- [v2 契约说明](docs/v2-contract.zh-CN.md) · [English](docs/v2-contract.md)

CI 会编译包并运行单元测试；真机安装/升级仍是最终验收关卡。
