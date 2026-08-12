# PrivateSigner iOS v2 接入指南

项目型 App 只知道稳定的 `projectID`；项目版本目录、源 IPA 身份和签名 Profile 策略由 Worker 管理。所有客户端操作统一使用 v2 契约和现有 `SIGNING_REQUEST_TOKEN`。

## 1. 引入包

App 应固定到已验收的 immutable tag 或 commit。项目自更新至少使用 `PrivateSignerKit` 和 `PrivateSignerSelfUpdate`；只有需要现成 SwiftUI 界面时再加 `PrivateSignerUI`。

## 2. 保存 Worker 配置

```swift
let keychain = SignerKeychainConfiguration(
    service: "com.example.app.private-signer",
    configurationAccessGroup: "TEAMID.com.example.app"
)
let store = SignerConfigurationStore(keychain: keychain)
```

使用 `SignerConfigurationStore` 保存 Worker 地址和现有 v2 Signing Request Token。项目发现、Profile 发现、自更新和通用签名都使用同一个凭据。

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

不要把 Profile ID、GitHub repository、IPA URL、latest version 或源 digest 编译进 App。这些都是 Worker 运行时状态。

## 4. 检查更新

```swift
let update = try await coordinator.updateStatus()
let candidate = update.updateAvailable ? update.targetVersion : nil
let profiles = update.profiles.filter(\.signable)
let selectedProfile = profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
```

是否存在更新由 Worker 判断；SDK 不自行比较 GitHub Release。

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

项目签名通过 `POST /v2/sign/jobs` 只提交 `project_id`、`version_id`、Profile 选择和签名行为。`ProjectSigningOptions` 不提供 `source_url`、源 digest、expected source version/build。

## 6. 续签当前安装版本

```swift
if coordinator.needsRenewal(within: 3) {
    let result = try await coordinator.requestRenewal(profileID: selectedProfile)
}
```

续签要求 Worker 对 `currentVersion` 对应的确切 ProjectVersion 重新签名。如果该版本未知或源已不可用，会明确失败，不会猜 IPA URL。

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

界面从 Worker 获取 Profile 列表并显示 Picker，不接受宿主注入的魔法默认 Profile ID。

## 8. 通用签名

```swift
let profiles = try await client.profiles()
let options = SigningOptions(profileID: profiles.first!.id)
let job = try await client.createURLJob(sourceURL: ipaURL, options: options)
```

通用签名使用相同 v2 Token，并使用 Worker 返回的 Profile ID。

## 验收

1. `verifyConfiguration()` 使用现有 Signing Request Token 能识别 v2 Worker。
2. App 自更新代码中只包含稳定 `projectID`，没有硬编码 Profile ID 和 unsigned IPA URL。
3. `projectUpdate` 返回 Worker 管理的目标 ProjectVersion 和可签 Profile。
4. 使用其 `versionID` + Profile 可以成功创建项目签名 Job。
5. Worker 上更换默认/允许 Profile 后，不需要重新编译 App。
6. 真机 `.installedApp` OTA 能覆盖当前安装版本。
