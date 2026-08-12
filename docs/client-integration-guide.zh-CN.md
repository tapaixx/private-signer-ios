# PrivateSigner iOS v3 接入指南

v3 是一次破坏性的 bug 修复协议。项目型 App 只知道稳定的 `projectID`；项目版本目录、源 IPA 身份和签名 Profile 策略全部由 Worker 管理。

## 1. 引入包

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.3.0")
```

项目自更新至少使用 `PrivateSignerKit` 和 `PrivateSignerSelfUpdate`；只有需要现成 SwiftUI 界面时再加 `PrivateSignerUI`。

## 2. 保存 Worker 配置

```swift
let keychain = SignerKeychainConfiguration(
    service: "com.example.app.private-signer",
    configurationAccessGroup: "TEAMID.com.example.app"
)
let store = SignerConfigurationStore(keychain: keychain)
```

使用 `SignerConfigurationStore` 保存 v3 Worker 地址和 scoped client token。普通自更新 App 的 token 通常只需要：

- `catalog:read`
- `sign:create`
- `jobs:control`
- 访问本 App 对应 project 的权限
- 访问该 project 允许的 Profile 权限

除非这个 App 本身就是通用签名器，否则不要给它 `generic-url-sign` / `upload-sign`。

## 3. App 只编译稳定 projectID

```swift
let coordinator = SelfUpdateCoordinator(
    store: store,
    projectID: "my-app",
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)",
    installedBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
)
```

不要把 Profile ID、GitHub repository、IPA URL、latest version 或源 digest 编译进 App。这些都是 Worker 的运行时状态。

## 4. 检查更新

```swift
let update = try await coordinator.updateStatus()
let candidate = update.updateAvailable ? update.targetVersion : nil
let profiles = update.profiles.filter(\.signable)
let selectedProfile = profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
```

是否存在更新由 Worker 判断；SDK 不再自行比较 GitHub Release。

## 5. 请求项目签名

```swift
if let candidate, let selectedProfile {
    var result = try await coordinator.requestSignedBuild(
        of: candidate,
        target: .installedApp,
        profileID: selectedProfile
    )
    while result.job.isActive {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        result = try await coordinator.refresh(jobID: result.job.jobID)
    }
}
```

项目签名只提交 `project_id`、`version_id`、Profile 选择和签名行为参数。`ProjectSigningOptions` 故意不提供 `source_url`、源 digest、expected source version/build，防止客户端覆盖 Worker 事实。

## 6. 续签当前安装版本

```swift
if coordinator.needsRenewal(within: 3) {
    let result = try await coordinator.requestRenewal(profileID: selectedProfile)
}
```

续签会要求 Worker 对 `currentVersion` 对应的确切 ProjectVersion 重新签名。如果该版本未知或源已不可用，会明确失败，不会猜一个 IPA URL。

## 7. SwiftUI

```swift
let context = SignerUIContext(
    keychain: keychain,
    userAgent: "MyApp/\(currentVersion)"
)

SelfUpdateView(
    context: context,
    projectID: "my-app",
    currentVersion: currentVersion
)
```

界面会从 Worker 获取 Profile 列表并显示 Picker。宿主不再传 `defaultProfileID`。

## 8. 通用签名是另一种能力

只有拥有 generic scope 的 Principal 才应该调用：

```swift
let profiles = try await client.profiles()
let options = SigningOptions(profileID: profiles.first!.id)
let job = try await client.createURLJob(sourceURL: ipaURL, options: options)
```

通用签名同样应该使用 Worker 返回的 Profile ID，不要硬编码或自行发明。

## 9. v3 删除的旧接口

以下内容被有意删除：

- `/v2` 客户端契约
- `ReleaseSource`
- `GitHubReleaseSource`
- `SignerUIContext.defaultProfileID`
- `personal-main` 的任何特殊语义

## 验收

1. `verifyConfiguration()` 能识别 v3 Worker。
2. App 自更新代码中只包含稳定 `projectID`，没有 Profile ID 和 unsigned IPA URL。
3. `projectUpdate` 返回 Worker 管理的目标 ProjectVersion 和可签 Profile。
4. 使用其 `versionID` + Profile 可以成功创建项目签名 Job。
5. project-scoped token 请求任意 URL/upload 签名会得到 `403`。
6. Worker 上更换默认/允许 Profile 后，不需要重新编译 App。
7. 真机 `.installedApp` OTA 能覆盖当前安装版本。
