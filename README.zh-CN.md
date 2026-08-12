# Private Signer for iOS

[English](README.md) · **简体中文**

一个 Swift 包，让 iOS/iPadOS App 能向 [Private IPA Signer](https://github.com/nnnmdzz/private-signer)
部署请求私有 IPA 签名，并通过 OTA 安装签名结果 —— 包括更新它自己。

## 这个包解决什么

签名服务本身是应用无关的：给它一个可重签的 IPA，它还你一个绑定设备的已签名 IPA。本包是这个契约的
客户端一半，这样接入方就不必重新实现分片上传协议、任务状态机、让配置在重新签名后仍能存活的 Keychain
规则，以及那些防止"自更新"悄悄装出第二个 App 的身份校验。

**本包中没有任何机密。** Worker 地址和 Signing Request Token 由使用者输入、存在设备 Keychain 里。
这正是本仓库可以公开、而签名服务保持私有的原因。

## 三个产物

| 产物 | 依赖 | 提供什么 |
| --- | --- | --- |
| `PrivateSignerKit` | — | 契约本身：配置存储、`/v2` 客户端、交付链接、OTA 安装 URL、错误模型。 |
| `PrivateSignerSelfUpdate` | Kit | `ReleaseSource`、`GitHubReleaseSource`、版本比较、`SelfUpdateCoordinator`。 |
| `PrivateSignerUI` | Kit + SelfUpdate | 现成的 SwiftUI 界面（中文 + 英文）。**便利品**——需要不同文案就基于 Kit 自己写。 |

## 安装

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.2.0")
```

**锁精确版本。** 自更新链路一旦坏掉，是没法靠自更新修回来的。

## 接入

读 **[docs/client-integration-guide.zh-CN.md](docs/client-integration-guide.zh-CN.md)** ——
它按可被 AI agent 逐步执行的方式编写，末尾有能实际运行的验收断言。
[英文规范源](docs/client-integration-guide.md)。

## 最小自更新示例

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
    releaseSource: GitHubReleaseSource(
        repository: "owner/name",
        assetNameTemplate: "MyApp-{tag}-unsigned.ipa",
        userAgent: "MyApp/\(currentVersion)"
    ),
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)"
)

if let candidate = try await coordinator.checkForUpdate() {
    var result = try await coordinator.requestSignedBuild(of: candidate)   // .installedApp
    while result.job.isActive {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        result = try await coordinator.refresh(jobID: result.job.jobID)
    }
    if let installURL = result.installationURL {
        await UIApplication.shared.open(installURL)
    }
}
```

## 两个容易踩的坑

**Stable Configuration Group。** 在 split 签名下，默认 Keychain access group 会随 provisioning
profile 变化，所以依赖默认组的 App 每自更新一次就丢一次配置。必须显式指定一个组，并让每个签名请求
都带上它 —— `SelfUpdateCoordinator` 会自动做这件事。详见指南 §3。

**原地升级 vs 并排副本。** `SelfUpdateTarget` 有两个 case 而不是一个可选 Bundle ID，因为传错的后果
是桌面上多一个图标、旧版本还在跑，而用户会以为更新成功了。详见指南 §6。

## API 参考

完整公开接口，附带每个尖角背后的理由：[docs/api-reference.zh-CN.md](docs/api-reference.zh-CN.md)。

## 领域模型

本包用到的术语定义在 [CONTEXT.zh-CN.md](CONTEXT.zh-CN.md)，与签名服务自己的术语表逐字一致。

## 验证状态

CI 在每次推送时编译本包并跑单元测试。**CI 无法证明签名后的 IPA 能装到真机上。**
真机的安装、升级、多开副本验证是最终验收关卡，必须由人拿着手机完成。
