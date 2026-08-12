# API 参考

[English](api-reference.md) · **简体中文**

三个产物的完整公开接口。想知道**怎么接入**看
[接入指南](client-integration-guide.zh-CN.md)；这里回答的是"某个类型到底有什么"。

---

## 目录

- [PrivateSignerKit](#privatesignerkit) — 契约本身
- [PrivateSignerSelfUpdate](#privatesignerselfupdate) — 自更新与签名续期
- [PrivateSignerUI](#privatesignerui) — 现成界面
- [错误码总表](#错误码总表)

---

## PrivateSignerKit

唯一的契约。UI 和自更新都建立在它之上，**没有它做不到的事**。

### `SignerConfiguration`

Worker 地址与 Signing Request Token。

```swift
public struct SignerConfiguration: Codable, Equatable {
    public let workerURL: URL
    public let requestToken: String
    public init(workerURL: URL, requestToken: String)
}
```

⚠️ 存储时 token 的 JSON 键固定为 `personalToken`。这是为了让本包出现之前就已安装的客户端仍能读到自己的配置，**不要"顺手改正"它**。

### `SignerEnvironment`

具名环境，让同一个 App 同时持有生产和测试两套凭据。

```swift
public struct SignerEnvironment: Hashable, CustomStringConvertible {
    public static let `default`: SignerEnvironment
    public let name: String
    public init?(name: String)   // 只接受 [A-Za-z0-9_-]，最长 64
}
```

`default` 的 Keychain account **不带后缀**——这正是已安装客户端升级后配置仍在的原因。具名环境追加 `.<name>`。

### `SignerKeychainConfiguration`

```swift
public struct SignerKeychainConfiguration {
    public let service: String                    // 惯例：<你的.bundle.id>.private-signer
    public let account: String                    // 默认 "worker-configuration"
    public let configurationAccessGroup: String   // Stable Configuration Group，必填
    public let legacyAccessGroups: [String]       // 已发布版本写过的旧组

    public init(service: String,
                account: String = "worker-configuration",
                configurationAccessGroup: String,
                legacyAccessGroups: [String] = [])
}
```

**`configurationAccessGroup` 是整个接入最容易做错的地方。** 详见[接入指南 §3](client-integration-guide.zh-CN.md#3-确定-stable-configuration-group)。

### `SignerConfigurationStore`

```swift
public struct SignerConfigurationStore {
    public let keychain: SignerKeychainConfiguration
    public let environment: SignerEnvironment
    public init(keychain: SignerKeychainConfiguration, environment: SignerEnvironment = .default)

    /// 每个签名请求都要带上它，否则签出来的 App 读不到自己的配置。
    public var authorizedAccessGroups: [String] { get }

    public func load() throws -> SignerConfiguration?
    @discardableResult
    public func save(workerURL: String, requestToken: String) throws -> SignerConfiguration
    public func clear() throws

    /// 不落盘地校验用户输入的地址：仅 HTTPS、无内嵌凭据、无 query/fragment。
    public static func validatedWorkerURL(_ rawValue: String) throws -> URL
}
```

`load()` 会依次尝试 stable 组 → legacy 组 → 默认组，命中非 stable 组时**当场迁移**过去。

### `SigningOptions`

```swift
public struct SigningOptions: Encodable, Equatable {
    public var signingMode: SigningMode                  // 默认 .split
    public var targetBundleIdentifier: String?           // nil 则沿用来源
    public var profileID: String?                        // nil 则用服务端默认集合
    public var keychainAccessGroups: [String]
    public var embeddedBundlePolicy: CompatibilityPolicy // 默认 .stripUnsupported
    public var entitlementPolicy: CompatibilityPolicy    // 默认 .stripUnsupported
    public var expectedSHA256: String?
    public var expectedVersion: String?
    public var expectedBuild: String?
}

public enum SigningMode: String, Codable, CaseIterable, Identifiable { case split, standard }
public enum CompatibilityPolicy: String, Codable {
    case stripUnsupported = "strip_unsupported"
    case requireAll = "require_all"
}
```

**永远显式传 `signingMode`。** 服务端不会替你推断，而 split 和 standard 签出来是两个不同的产物。

```swift
/// 把 GitHub 的 `sha256:<hex>` 归一化成裸 hex；不是 64 位十六进制就返回 nil。
public func normalizedSHA256(_ rawValue: String?) -> String?
```

### `SigningClient`

```swift
public struct SigningClient {
    public static let maximumSourceBytes: Int   // 100 MiB
    public static let maximumPartBytes: Int     // 8 MiB

    public init(configuration: SignerConfiguration,
                userAgent: String,
                transport: SigningTransport? = nil)

    // 创建任务
    public func createURLJob(sourceURL: URL, options: SigningOptions) async throws -> SigningJob
    public func uploadAndCreateJob(filename: String, data: Data, options: SigningOptions) async throws -> SigningJob
    public func uploadAndCreateJob(fileURL: URL, options: SigningOptions) async throws -> SigningJob

    // 轮询与生命周期
    public func job(id: String) async throws -> SigningJob
    public func history() async throws -> [SigningJob]      // 自动翻完所有页
    public func retry(jobID: String) async throws -> SigningJob
    public func cancel(jobID: String) async throws -> SigningJob
    public func links(jobID: String) async throws -> DeliveryLinks

    // 配置自检
    public func health() async throws -> ServiceHealth
    public func verifyConfiguration() async -> ConfigurationVerification
}
```

`transport` 是测试接缝：

```swift
public protocol SigningTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

`URLSession` 已经满足它。

### `SigningJob` / `SigningJobStatus` / `DeliveryLinks`

```swift
public struct SigningJob: Decodable, Identifiable, Equatable {
    public let jobID, status, signingMode, source, createdAt, updatedAt: /* 见源码 */
    public let attempt: Int?
    public let errorCode, message: String?
    public let actualBundleIdentifier, actualVersion, actualBuild, actualTitle, finalSHA256: String?
    public let warnings: [String]?
    public var isActive: Bool
}

public enum SigningJobStatus: Equatable, Decodable {
    case dispatching, queued, dispatchFailed, signing, following, completed, failed, cancelled
    case unknown(String)          // 服务端学会了新状态时不崩
    public var isActive: Bool     // dispatching / queued / signing / following
    public var isFailure: Bool    // failed / dispatchFailed
}

public struct DeliveryLinks: Decodable, Equatable {
    public let manifestURL, installURL, exportURL: URL
    public let expiresAt: String   // 15 分钟，过期重新调 links()
}
```

⚠️ **遇到 `.unknown` 既不当作进行中也不当作失败，继续轮询。** 不要因为服务端多了个状态就崩溃。

### `ServiceHealth` / `ConfigurationVerification`

```swift
public struct ServiceHealth: Decodable, Equatable {
    public static let supportedContracts: Set<String>   // ["v2"]
    public let ok: Bool
    public let contract: String?
}

public enum ConfigurationVerification: Equatable {
    case usable
    case usableWithUndeclaredContract   // 能用，但 Worker 版本较旧没声明契约
    case notASigner                     // 地址填错了
    case unsupportedContract(String)
    case invalidToken                   // 地址对，token 错
    case unreachable(String)

    public var isUsable: Bool
    public var code: String       // 稳定标识，用来分支
    public var message: String    // 本地化文案，用来展示
}
```

**这是"地址填错"和"token 填错"唯一能被区分开的地方**，配置界面应该用它。

### `OTAInstallation`

```swift
public enum OTAInstallation {
    /// 把 HTTPS manifest 包成 iOS 需要的 itms-services:// 地址；非 HTTPS 返回 nil。
    public static func installationURL(manifestURL: URL) -> URL?
}
```

---

## PrivateSignerSelfUpdate

### `ReleaseSource`

**接入方唯一需要实现的东西。**

```swift
public protocol ReleaseSource {
    /// 严格新于 currentVersion 的最新候选；已是最新则返回 nil。
    func latestRelease(currentVersion: String) async throws -> ReleaseCandidate?

    /// 与指定版本完全相同的那个 release，仅用于签名续期。
    /// 默认返回 nil，即该 source 不支持续期。
    func release(matching version: String) async throws -> ReleaseCandidate?
}

public struct ReleaseCandidate: Equatable {
    public let version: String
    public let ipaURL: URL
    public let expectedSHA256: String?
    public let notes: String?
}
```

### `GitHubReleaseSource`

覆盖绝大多数场景的内置实现。

```swift
public struct GitHubReleaseSource: ReleaseSource {
    public init(repository: String,                    // "owner/name"
                assetNameTemplate: String,             // "MyApp-{tag}-unsigned.ipa"
                userAgent: String,
                includePrereleases: Bool = false,
                ordering: VersionOrdering = BuildTaggedVersionOrdering(),
                pageSize: Int = 30,
                transport: SigningTransport? = nil)
}
```

模板占位符：`{tag}` 是原样发布 tag（`v1.0.5-0006`），`{version}` 是去掉开头 `v` 的同一个值。

### `VersionOrdering`

```swift
public protocol VersionOrdering {
    /// 任一侧无法解析时返回 nil，调用方据此跳过而不是猜。
    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult?
}

public struct BuildTaggedVersionOrdering: VersionOrdering {}  // vX.Y.Z-NNNN（默认）
public struct DottedVersionOrdering: VersionOrdering {}       // 1.2.3 / v2.0

public struct BuildTaggedVersion: Comparable, CustomStringConvertible {
    public init?(_ rawValue: String)
    public let major, minor, patch, build, buildDigits: Int
    public var tagName: String   // 原样还原发布时的 tag
}
```

**不要为了迁就本包改你的 tag 规范**——实现 `VersionOrdering` 即可。

### `SelfUpdateCoordinator`

```swift
public struct SelfUpdateCoordinator {
    public init(store: SignerConfigurationStore,
                releaseSource: ReleaseSource,
                currentVersion: String,
                userAgent: String,
                installedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
                profileID: String? = nil,
                signingMode: SigningMode = .split,
                embeddedBundlePolicy: CompatibilityPolicy = .stripUnsupported,
                entitlementPolicy: CompatibilityPolicy = .stripUnsupported,
                transport: SigningTransport? = nil)

    // 更新
    public func checkForUpdate() async throws -> ReleaseCandidate?
    public func requestSignedBuild(of candidate: ReleaseCandidate,
                                   target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult
    public func refresh(jobID: String, target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult

    // 签名续期
    public func installedSignature(bundle: Bundle = .main) -> InstalledSignature?
    public func needsRenewal(within days: Double = 3, bundle: Bundle = .main) -> Bool
    public func requestRenewal(target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult
}
```

### `SelfUpdateTarget` / `SelfUpdateResult`

```swift
public enum SelfUpdateTarget: Equatable {
    case installedApp                       // 替换当前 App
    case sideBySideClone(bundleID: String)  // 并排装第二个
}

public struct SelfUpdateResult: Equatable {
    public let job: SigningJob
    public let links: DeliveryLinks?
    public let targetBundleIdentifier: String
    public let willReplaceInstalledApp: Bool   // false = 会多出一个图标
    public var isReadyToInstall: Bool
    public var installationURL: URL?
}
```

**显示安装提示前先看 `willReplaceInstalledApp`**，并明说接下来是哪一种。

### `InstalledSignature`

```swift
public struct InstalledSignature: Equatable {
    public let expiresAt: Date
    public let profileName, profileUUID, teamIdentifier, applicationIdentifier: String?
    public let isShortLived: Bool     // Apple 免费账号的 7 天 profile
    public var isExpired: Bool
    public var daysRemaining: Double
    public func expires(within days: Double) -> Bool
}

public enum InstalledSignatureReader {
    public static func read(bundle: Bundle = .main) -> InstalledSignature?
}
```

`isShortLived == true` 时**不要提供续期按钮**——7 天 profile 任何 API 都续不了，只能用 Xcode 重新签发。

---

## PrivateSignerUI

便利品，不是契约。需要不同文案或布局就基于 Kit 自己写。

```swift
public struct SignerUIContext {
    public init(keychain: SignerKeychainConfiguration,
                environments: [SignerEnvironment] = [.default],
                userAgent: String,
                defaultProfileID: String? = nil)
    public func store(for environment: SignerEnvironment) -> SignerConfigurationStore
}

public struct SignerConfigurationEditorView: View {
    public init(context: SignerUIContext,
                environment: SignerEnvironment = .default,
                onSaved: @escaping (SignerConfiguration, SignerEnvironment) -> Void)
}

public struct SigningJobsView: View {
    public init(context: SignerUIContext, environment: SignerEnvironment = .default)
}

public struct SelfUpdateView: View {
    public init(context: SignerUIContext,
                releaseSource: ReleaseSource,
                currentVersion: String,
                installedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
                environment: SignerEnvironment = .default,
                signingMode: SigningMode = .split)
}
```

界面自带简体中文与英文，跟随系统语言。仅 iOS。

---

## 错误码总表

每个错误类型都同时提供**稳定的 `code`** 和**本地化的 `errorDescription`**。
**用 `code` 做分支，用 `errorDescription` 做展示，永远不要解析文案。**

### `SignerConfigurationError`

| code | 含义 |
|---|---|
| `invalid_worker_url` | 地址不是合法 HTTPS，或内嵌了凭据 |
| `empty_token` | Token 为空 |
| `keychain` | Keychain 操作失败（带 `OSStatus`） |
| `invalid_stored_data` | 已存配置无法解码 |

### `SigningClientError`

| code | 含义 |
|---|---|
| `invalid_url` | 无法组成请求地址，或不是 HTTPS |
| `invalid_response` | 服务端返回无法解析的数据 |
| `unauthorized` | Token 被拒（HTTP 401/403） |
| `source_too_large` | 超过 100 MiB |
| `server` | 其他 HTTP 错误，带状态码与服务端消息 |

### `SelfUpdateError`

| code | 含义 |
|---|---|
| `not_configured` | 还没配置签名服务 |
| `missing_bundle_identifier` | 拿不到 Bundle ID |
| `unauthorized` | 鉴权失败 |
| `unexpected_bundle_identifier` | **签名结果的身份与请求不符，绝不能安装** |
| `invalid_manifest` | 没有返回有效的 HTTPS manifest |
| `network` | 网络失败 |
| `signature_not_readable` | 读不到当前签名的有效期 |
| `current_version_source_unavailable` | 找不到当前版本对应的 release，无法续期 |

### `GitHubReleaseSourceError`

| code | 含义 |
|---|---|
| `invalid_current_version` | 当前版本号无法被 ordering 解析 |
| `invalid_response` | GitHub 返回无法识别的数据 |
| `no_valid_release` | 没有版本号可识别的正式 release |
| `missing_asset` | **release 存在但附件名对不上——模板写错了，不是 release 有问题** |
| `network` | 网络失败 |
