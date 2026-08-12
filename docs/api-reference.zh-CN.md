# PrivateSigner iOS v3 API 参考

## PrivateSignerKit

### `SignerConfiguration`
保存 HTTPS Worker 地址和 scoped v3 client token。

### `SignerConfigurationStore`
把配置保存在指定 Keychain access group 中。App 会反复重签时必须使用稳定 access group。

### `SigningClient`
v3 HTTP 客户端。

项目目录：

- `projects() -> [SigningProject]`
- `project(id:) -> ProjectDetail`
- `projectVersions(projectID:) -> [ProjectVersion]`
- `projectUpdate(projectID:currentVersion:) -> ProjectUpdate`
- `profiles(projectID:) -> [ProfileCapability]`

项目签名：

- `createProjectJob(projectID:versionID:options:) -> SigningJob`

Principal 拥有相应 scope 时的通用签名：

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

### `SigningProject`
授权 Principal 能看到的安全项目元数据：稳定 ID/名称、Bundle ID、版本规则、默认 Profile 和同步状态。

### `ProjectVersion`
Worker 管理的不可变源版本。核心字段包括 `versionID`、版本号、GitHub release/asset 身份、digest 状态和生命周期状态。它故意不暴露 unsigned IPA URL。

### `ProfileCapability`
客户端安全视图：Profile ID、显示名、过期时间、short-lived、是否可签、是否为项目默认。原始 mobileprovision、UDID、证书私钥都不会通过这里暴露。

### `ProjectUpdate`
Worker 的权威更新判断：项目、当前版本是否已知、`updateAvailable`、目标版本和项目允许的 Profile。

### `ProjectSigningOptions`
对 Worker 管理的 ProjectVersion，客户端只能选择：

- signing mode
- target Bundle ID
- Profile ID
- Keychain access groups
- embedded bundle policy
- entitlement policy

它故意不能表达 `source_url`、源 digest、expected source version/build。

### `SigningOptions`
通用 URL/upload 签名参数。因为源是客户端提供的，所以仍允许 expected digest/version/build 断言。

### `SigningJob`
异步签名 Job。活动状态需要轮询；完成后再通过 `DeliveryLinks` 获取短时安装/导出链接。

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

- `updateStatus()`：完整 Worker 更新判断和 Profile 列表。
- `checkForUpdate()`：返回目标 `ProjectVersion` 或 `nil`。
- `availableProfiles()`：项目可用 Profile capability。
- `requestSignedBuild(of:target:profileID:)`：签指定不可变 ProjectVersion。
- `refresh(jobID:target:)`：刷新 Job，完成后取得 links。
- `installedSignature()` / `needsRenewal(within:)`：检查当前嵌入 Profile。
- `requestRenewal(target:profileID:)`：续签当前安装版本对应的确切 ProjectVersion。

`SelfUpdateCandidate` 是 `ProjectVersion` 的 typealias。v3 不再存在 `ReleaseSource` / `GitHubReleaseSource`。

## PrivateSignerUI

### `SignerUIContext`
只包含 Keychain 配置、环境和 user agent，不包含 Profile ID。

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
可选的通用 URL/upload 签名 UI。它会发现当前 Principal 可见的 Profile，并要求提交前选择。若 project-scoped Principal 没有 generic scope，Worker 会拒绝通用签名。

## 契约兼容性

本包只支持 Worker `v3`。`/v2`、宿主注入默认 Profile、客户端 GitHub Release 发现和具有特殊含义的 `personal-main` 都被明确移除。
