# PrivateSigner iOS v2 API 参考

## PrivateSignerKit

### `SignerConfiguration`
保存 HTTPS Worker 地址和现有 v2 `SIGNING_REQUEST_TOKEN` 值。

### `SignerConfigurationStore`
把配置保存在指定 Keychain access group 中。App 会反复重签时必须使用稳定 access group。

### `SigningClient`
唯一的 v2 HTTP 客户端。

项目目录：

- `projects() -> [SigningProject]`
- `project(id:) -> ProjectDetail`
- `projectVersions(projectID:) -> [ProjectVersion]`
- `projectUpdate(projectID:currentVersion:) -> ProjectUpdate`
- `profiles(projectID:) -> [ProfileCapability]`

项目签名：

- `createProjectJob(projectID:versionID:options:) -> SigningJob`

通用签名：

- `createURLJob(sourceURL:options:)`
- `uploadAndCreateJob(filename:data:options:)`
- `uploadAndCreateJob(fileURL:options:)`

Job 生命周期：

- `job(id:)`
- `history()`
- `retry(jobID:)`
- `cancel(jobID:)`
- `links(jobID:)`

服务验证：

- `health()`
- `verifyConfiguration()`

以上所有认证接口都使用同一个配置 Bearer Token。

### `SigningProject`
安全项目元数据：稳定 ID/名称、Bundle ID、版本规则、项目默认 Profile 和同步状态。

### `ProjectVersion`
Worker 管理的源版本。核心字段包括 `versionID`、版本号、GitHub release/asset 身份、digest 状态和生命周期状态。它故意不暴露 unsigned IPA URL。

### `ProfileCapability`
客户端安全视图：Profile ID、显示名、过期时间、short-lived、是否可签、是否为项目默认。原始 provisioning 数据、UDID、证书私钥不会通过这里暴露。

### `ProjectUpdate`
Worker 的更新判断：项目、当前版本是否已知、`updateAvailable`、目标版本和项目可用 Profile。

### `ProjectSigningOptions`
对 Worker 管理的 ProjectVersion，客户端只能选择：

- signing mode
- target Bundle ID
- Profile ID
- Keychain access groups
- embedded bundle policy
- entitlement policy

它不能表达 source URL、源 digest、expected source version/build；这些在 Project Job 中由服务端维护。

### `SigningOptions`
通用 URL/upload 签名参数。通用源由客户端提供，所以仍允许 expected digest/version/build 断言。

### `SigningJob`
异步签名 Job。活动状态需要轮询；完成后通过 `DeliveryLinks` 获取短时安装/导出链接。

### `DeliveryLinks`
Worker 签发的短时 manifest/export/install URL。

## PrivateSignerSelfUpdate

### `SelfUpdateCoordinator`

```swift
SelfUpdateCoordinator(
    store: store,
    projectID: "my-app",
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)"
)
```

主要接口：

- `updateStatus()`：Worker 更新判断和 Profile 列表。
- `checkForUpdate()`：返回目标 `ProjectVersion` 或 `nil`。
- `availableProfiles()`：项目可用 Profile capability。
- `requestSignedBuild(of:target:profileID:)`：签指定 ProjectVersion。
- `refresh(jobID:target:)`：刷新 Job，完成后取得 links。
- `installedSignature()` / `needsRenewal(within:)`：检查当前嵌入 Profile。
- `requestRenewal(target:profileID:)`：当前版本存在于 Worker 目录时，续签该确切 ProjectVersion。

`SelfUpdateCandidate` 是 `ProjectVersion` 的 typealias。项目自更新不再由客户端查 GitHub Release。

## PrivateSignerUI

### `SignerUIContext`
只包含 Keychain 配置、环境和 user agent，不包含硬编码 Profile ID。

### `SelfUpdateView`

```swift
SelfUpdateView(
    context: context,
    projectID: "my-app",
    currentVersion: currentVersion
)
```

Profile 由 Worker 发现并以 Picker 呈现。

### `SigningJobsView`
可选的通用 URL/upload 签名 UI。它会发现可用 Profile，并要求提交前明确选择。

## 契约兼容性

本包只支持 Worker `v2`。宿主注入魔法 Profile 默认值、客户端 GitHub Release 发现以及对历史 Profile 名称的特殊处理都不支持。
