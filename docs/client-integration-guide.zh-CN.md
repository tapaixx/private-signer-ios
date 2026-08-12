# Private IPA Signer — 客户端接入指南

[English](client-integration-guide.md) · **简体中文**

本指南用于给一个 iOS/iPadOS 项目加上私有 IPA 签名、OTA 交付，以及可选的自更新能力。它按可被 AI
编码 agent 逐步执行的方式编写，末尾给出可实际运行的验收断言。

本文是 [client-integration-guide.md](client-integration-guide.md) 的翻译。**两者冲突时以英文版为准**，
因为术语的唯一定义在英文侧。

**给按本指南执行的 agent 的停止规则：**

- [§1](#1-先收集这些值) 里的值如果拿不到，**停下来问人**。不要编造 Team ID、Bundle ID、Worker 地址或 Token。
- 绝不把 Signing Request Token 写进源码、构建设置、plist、测试固件、日志或提交信息。
- 不要汇报"接入已生效"。你无法验证这一点。[§7](#7-验收) 写明了什么你能验证、什么只有拿着真机的人能验证。

---

## 1. 先收集这些值

| 值 | 示例 | 来源 |
| --- | --- | --- |
| Apple Team ID | `4JJ849C5Q2` | Apple 开发者账号；也是任何已有 access group 的前缀 |
| 已安装 Bundle ID | `com.example.app` | 宿主 App 的 `PRODUCT_BUNDLE_IDENTIFIER` |
| Stable Configuration Group | `4JJ849C5Q2.com.example.app` | 由你决定 — 见 [§3](#3-确定-stable-configuration-group) |
| 历史 access group | `4JJ849C5Q2.old.identifier` | 仅当已发布版本把配置存在别处时才需要 |
| Worker 地址 | `https://signer.example.workers.dev` | Private IPA Signer 部署地址。**由用户运行时输入，绝不编译进包** |
| Signing Request Token | *(机密)* | 同上，由用户运行时输入 |
| Profile ID | `personal-main` | 签名服务已配置的 profile 集合；传 `nil` 表示用其默认值 |
| Release 仓库 | `owner/name` | 仅在用 GitHub Releases 做自更新时需要 |
| Release 附件名 | `MyApp-{tag}-unsigned.ipa` | 你的发布流程实际产出的附件文件名 |
| 版本号 | `1.0.5-0006` | App 运行时如何知道自己的版本 |

Worker 地址和 Token 是**用户配置，不是构建配置**。公开仓库一旦把它们编译进去，等于泄露了完整签名权限。

---

## 2. 添加依赖

Swift Package Manager：

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.2.0")
```

用 `exact:` 而不是 `from:`。如果自更新是你唯一的发版通道，一个会自己漂移的依赖可能恰好破坏那个本来
能救你的机制。

**XcodeGen** 项目在 `project.yml` 里加：

```yaml
packages:
  PrivateSigner:
    url: https://github.com/nnnmdzz/private-signer-ios.git
    exactVersion: 0.2.0

targets:
  YourApp:
    dependencies:
      - package: PrivateSigner
        product: PrivateSignerKit
      - package: PrivateSigner
        product: PrivateSignerSelfUpdate
      - package: PrivateSigner
        product: PrivateSignerUI      # 可选
```

如果你要自己写 UI、自己实现版本发现，只取 `PrivateSignerKit`。

最低要求：iOS 15、Swift 5.9。

---

## 3. 确定 Stable Configuration Group

**这一步是接入最容易做错的地方，而且故障是延迟发生的。**

Worker 地址和 Token 存在 Keychain 里。在 `split` 签名下，签名后的 `application-identifier` 来自
provisioning profile 而不是你的 Bundle ID —— 所以**默认** Keychain access group 会随 profile 变化。
依赖默认组的 App 在第一次自签更新时就会丢掉配置，用户必须重新输入一个他根本看不见的高熵 Token。

显式指定一个组、并要求签名器把它物化出来，才能避免这件事：

```swift
let store = SignerConfigurationStore(
    keychain: SignerKeychainConfiguration(
        service: "com.example.app.private-signer",
        configurationAccessGroup: "4JJ849C5Q2.com.example.app",
        legacyAccessGroups: []      // 已发布版本曾经写入过的组
    )
)
```

规则：

1. 该组必须**被签名器使用的 provisioning profile 授权**。签名器不会凭空造出 profile 允许范围之外的组
   —— 请求一个未授权的组会直接失败。
2. 这个 App 发出的每一个签名请求都必须带上该组。`SelfUpdateCoordinator` 会自动发送
   `store.authorizedAccessGroups`；如果你直接调用 `SigningClient`，需要自己传。
3. **未签名**的构建产物**不需要**在 `.entitlements` 里写 `keychain-access-groups`。该组是签名时按请求
   物化出来的。写进源码 entitlements 也允许，但不是必需。
4. 之后再改这个组，会让所有已安装客户端的配置成为孤儿。正确做法是把旧值加进 `legacyAccessGroups` ——
   读取时会回退到它，并当场把配置项迁移过来。

### 迁移一个已经在存配置的 App

如果已发布版本用了不同的 service、account 或 access group，保持旧值可读：

```swift
SignerKeychainConfiguration(
    service: "com.example.app.private-update",   // 已发布版本实际用的值
    account: "worker-configuration",             // 默认值，只有你的不一样时才改
    configurationAccessGroup: "4JJ849C5Q2.com.example.app",
    legacyAccessGroups: ["4JJ849C5Q2.previous.identifier"]
)
```

存储 JSON 里 Token 的键被固定为 `personalToken` 正是为了这个。**不要"顺手修正"它。**

---

## 4. 写 Integration Adapter

一个文件。所有应用特定的东西都放这里、且只放这里 —— 这是接入其余部分能够持续升级的前提。

```swift
import Foundation
import PrivateSignerKit
import PrivateSignerSelfUpdate

enum PrivateSigning {
    static let teamID = "4JJ849C5Q2"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.example.app"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var userAgent: String { "MyApp/\(currentVersion)" }

    static let store = SignerConfigurationStore(
        keychain: SignerKeychainConfiguration(
            service: "com.example.app.private-signer",
            configurationAccessGroup: "\(teamID).com.example.app"
        )
    )

    static let releaseSource = GitHubReleaseSource(
        repository: "owner/name",
        assetNameTemplate: "MyApp-{tag}-unsigned.ipa",
        userAgent: userAgent
    )

    static var coordinator: SelfUpdateCoordinator {
        SelfUpdateCoordinator(
            store: store,
            releaseSource: releaseSource,
            currentVersion: currentVersion,
            userAgent: userAgent,
            installedBundleIdentifier: bundleID,
            profileID: "personal-main"
        )
    }

    static var uiContext: SignerUIContext {
        SignerUIContext(
            keychain: store.keychain,
            environments: [.default],
            userAgent: userAgent,
            defaultProfileID: "personal-main"
        )
    }
}
```

**版本号格式。** `GitHubReleaseSource` 默认用 `BuildTaggedVersionOrdering`，识别 `vX.Y.Z-NNNN`
（如 `v1.0.5-0006`）。如果你的 tag 是普通语义化版本，传 `ordering: DottedVersionOrdering()`。
如果是别的格式，自己实现 `VersionOrdering` —— **不要为了迁就本包去改你的 tag 规范**。

**附件名。** `{tag}` 是原样的发布 tag（`v1.0.5-0006`）；`{version}` 是去掉开头 `v` 的同一个值。
如果 release 存在但附件名对不上，调用会以 `missingAsset` 失败并带上 tag —— 这个错误意味着模板写错了，
不是 release 有问题。

---

## 5. 接入 UI

### 方案 A —— 用现成界面

```swift
import PrivateSignerUI

NavigationLink("签名更新") {
    SelfUpdateView(
        context: PrivateSigning.uiContext,
        releaseSource: PrivateSigning.releaseSource,
        currentVersion: PrivateSigning.currentVersion,
        installedBundleIdentifier: PrivateSigning.bundleID
    )
}

NavigationLink("私人 IPA 签名") {
    SigningJobsView(context: PrivateSigning.uiContext)
}
```

自带中文和英文。"安装为副本（多开）"在高级选项里，勾选后主按钮文案会随之改变。

### 方案 B —— 基于 Kit 自己写

需要不同文案或布局时走这条。完整契约都在 `PrivateSignerKit` 里；UI 产物没有任何特权。

---

## 6. 自更新：原地升级 vs 并排副本

```swift
guard let candidate = try await PrivateSigning.coordinator.checkForUpdate() else {
    return   // 已是最新
}

var result = try await PrivateSigning.coordinator.requestSignedBuild(
    of: candidate,
    target: .installedApp                              // 替换当前 App
    // target: .sideBySideClone(bundleID: "com.example.app.clone2")   // 新增一个 App
)

while result.job.isActive {
    try await Task.sleep(nanoseconds: 5_000_000_000)
    result = try await PrivateSigning.coordinator.refresh(jobID: result.job.jobID, target: target)
}

if let installURL = result.installationURL {
    await UIApplication.shared.open(installURL)
}
```

`SelfUpdateTarget` 用两个 case 而不是一个可选 Bundle ID，是因为两者的结果肉眼可见地不同，调用方不应该
能"不小心"选错。显示安装提示前先检查 `result.willReplaceInstalledApp`，并明确告诉用户接下来会发生哪一种。

几个值得在 UI 上讲清楚的事实：

- 每个不同的 `target_bundle_id` 是一个不同的请求指纹，所以 **N 个副本 = N 次真实签名任务**，它们之间
  不会互相复用。
- 副本会自动继承 Stable Configuration Group，因此不需要重新输入 Token。
- **已知限制：** iOS 可能在持有某 access group 的最后一个 App 被卸载时清除该组的 Keychain 项。如果卸载
  主 App 只留副本，已存配置可能保留、也可能丢失。这一点尚未验证，请当作风险而非保证。

### 轮询

不要快于每 5 秒一次，只在 App 处于前台、且 `job.isActive` 时轮询。签名跑在真实的 macOS runner 上，
紧凑轮询换不到任何东西，只会烧掉限流额度。

---

## 6b. 签名续期（Signature Renewal）

**签名过期不是"有新版本"**，本包把两者严格分开。`checkForUpdate()` 的含义仍然是"有更新的版本"——
把续期折进去会让它返回一个版本号等于当前版本的候选，从而破坏所有按这个语义写的调用方。

```swift
if let signature = PrivateSigning.coordinator.installedSignature() {
    // 免费账号的 profile 只有 7 天，且任何 API 都续不了，只能用 Xcode 重新签发。
    // 这种情况要直说，而不是给一个点了必然失败的按钮。
    if signature.isShortLived && signature.expires(within: 3) {
        show("签名 \(signature.daysRemaining.rounded()) 天后过期，需要用 Xcode 重新签发描述文件")
    } else if PrivateSigning.coordinator.needsRenewal(within: 3) {
        let result = try await PrivateSigning.coordinator.requestRenewal()   // 同一版本
        // …轮询和安装与普通更新完全一致
    }
}
```

`requestRenewal()` 需要找到**当前已安装版本**对应的那个 release，这是 `ReleaseSource` 上的第二个查找。
`GitHubReleaseSource` 已实现；自定义 source 不实现时默认返回 `nil`，续期会报
`current_version_source_unavailable`，而不是以别的方式失败。

**续期解决不了的事**：7 天 profile 意味着 App 每周都会失效，跟有没有新版本无关；而且每次续期最后仍然
需要人手动点安装。如果你处在这个情况，正确的解法是买付费开发者账号，不是这个 API。

---

## 7. 验收

### CI 能验证的部分

把下面这段加进你的测试。它拦的是那些"犯起来很便宜、发现起来很贵"的错误：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. 没有把签名凭据编译进去。
grep -rniE '(signing[_-]?request[_-]?token|personal[_-]?update[_-]?token)[[:space:]]*[=:][[:space:]]*"[^"]+"' \
  --include='*.swift' --include='*.plist' --include='*.xcconfig' --include='*.yml' . \
  && fail "疑似硬编码了签名 Token"

# 2. 没有把默认 Worker 地址编译进去。
grep -rniE 'https://[a-z0-9.-]*workers\.dev' --include='*.swift' . \
  && fail "硬编码了 Worker 地址"

# 3. 应用特定的值只出现在 adapter 里。
for symbol in GitHubReleaseSource SignerKeychainConfiguration; do
  hits=$(grep -rl "$symbol" --include='*.swift' Sources App Shared 2>/dev/null | grep -v 'PrivateSigningAdapter.swift' || true)
  [ -z "$hits" ] || fail "$symbol 在 adapter 之外被构造：$hits"
done

# 4. 自更新路径显式声明了 target。
grep -rn 'requestSignedBuild' --include='*.swift' . | grep -qv 'target:' \
  && fail "requestSignedBuild 调用没有显式 target"

echo "OK"
```

第 3 项里的路径要按你的工程结构调整，adapter 文件名按 [§4](#4-写-integration-adapter) 里你实际起的名字改。

### 只有拿着真机的人能验证的部分

macOS 上 `codesign --verify` 通过**并不**证明 iOS 能装上或能升级。下面每一条都需要真机：

- [ ] 签名 IPA 全新安装成功且能启动。
- [ ] **覆盖当前已安装版本升级**成功 —— 不能只测全新安装。
- [ ] Worker 地址和 Token 在那次升级后仍在，无需重新输入。
- [ ] 依赖 entitlement 的功能在签名后仍然正常（部分权限会按策略被移除 —— 去读签名报告）。
- [ ] 并排副本装成了**第二个** App，原来那个还能运行。
- [ ] 副本无需重新输入 Token 就能读到配置。
- [ ] 填错 Worker 地址和填错 Token 会给出**不同的**、可操作的提示。

**不要仅凭 CI 绿灯就发版。**

---

## 8. 失败处理

`ConfigurationVerification` 的存在就是为了把"手输配置最常出的两种错"区分开：

| 结果 | 含义 | 该告诉用户什么 |
| --- | --- | --- |
| `.usable` | 地址和 Token 都正常 | 继续 |
| `.usableWithUndeclaredContract` | 能用，但 Worker 版本早于 contract 字段 | 继续；建议升级 Worker |
| `.notASigner` | 有东西应答了，但它不是 Private IPA Signer | 检查地址 |
| `.unsupportedContract(v)` | 版本不匹配 | 升级 App 或 Worker |
| `.invalidToken` | 地址对，Token 被拒 | 只需重新输入 Token |
| `.unreachable(detail)` | 网络或 DNS 问题 | 展示 detail |

本包中每个错误类型都同时提供稳定的 `code` 和本地化的 `errorDescription`。
**用 `code` 做分支，用 `errorDescription` 做展示。** 永远不要去解析文案。

诊断信息请保留：HTTP 状态码、`error_code`、`message`、`job_id`、`attempt`、任务状态。
**永远不要记录 `Authorization` 头或交付链接 URL** —— 交付链接本质上是放在 query string 里的 bearer 凭据。

---

## 附录 A —— 原始 HTTP 契约

给非 Swift 客户端用。`PrivateSignerKit` 已经完整实现了这一节。

Base 为 Worker origin。鉴权：除 `/health` 和交付端点（它们带自己的签名 token）外，一律
`Authorization: Bearer <Signing Request Token>`。

| 端点 | 方法 | 用途 |
| --- | --- | --- |
| `/health` | GET | 免鉴权。`{"ok":true,"contract":"v2"}` |
| `/v2/sign/jobs` | POST | 创建或复用一个签名任务 |
| `/v2/sign/jobs` | GET | 分页历史，最新在前，`next_cursor` |
| `/v2/sign/jobs/<id>` | GET | 轮询单个任务 |
| `/v2/sign/jobs/<id>/retry` | POST | 重试失败任务 |
| `/v2/sign/jobs/<id>/cancel` | POST | 取消进行中任务 |
| `/v2/sign/jobs/<id>/links` | POST | 生成 15 分钟交付链接 |
| `/v2/uploads` | POST | 开始上传会话 |
| `/v2/uploads/<id>/parts/<n>` | PUT | 上传一个分片 |
| `/v2/uploads/<id>/complete` | POST | 结束上传 |
| `/v2/delivery/manifest?token=` | GET | OTA manifest |
| `/v2/delivery/artifact?token=` | GET | 签名后的 IPA |

创建任务的请求体 —— 只能带一个来源（`source_url` **或** `upload_id`），且必须显式带 `signing_mode`：

```json
{
  "source_url": "https://example.com/App.ipa",
  "signing_mode": "split",
  "target_bundle_id": "com.example.clone",
  "profile_id": "personal-main",
  "keychain_access_groups": ["TEAM.com.example.app"],
  "embedded_bundle_policy": "strip_unsupported",
  "entitlement_policy": "strip_unsupported",
  "expected_sha256": "<64 位十六进制，可选>"
}
```

任务状态：`dispatching`、`queued`、`dispatch_failed`、`signing`、`following`、`completed`、
`failed`、`cancelled`。**遇到不认识的状态，既不当作进行中也不当作失败，继续轮询** —— 不要因为服务端
学会了一个新状态就崩溃。

限制：来源 100 MiB；分片 8 MiB（用服务端返回的 `part_size`，不要写死）；最多 5 个进行中的上传会话、
每小时 20 个新会话、每小时 500 MiB 声明上传量。任务元数据保留 30 天，签名产物保留 7 天，交付链接
15 分钟（产物还在时可续期）。

HTTP 映射：

| 状态码 | 处理 |
| --- | --- |
| `2xx` | 解码并按返回状态继续 |
| `400` | 请求/选项/来源校验失败；展示服务端 `error` |
| `401` | Token 缺失、无效或已轮换；引导用户修复凭据 |
| `404` | 任务或上传已不存在；不要再假设它还在 |
| `409` | 生命周期冲突（上传未完成、任务不可重试、产物未就绪） |
| `410` | 来源/上传/产物已过期；重新获取 |
| `429` | 触发限流；退避并保留该操作 |
| `5xx` | 服务或调度失败；仅在操作语义允许时重试 |

---

## 附录 B —— 契约 vs 建议

- **契约**（只随服务变化）：可接受字段、状态集合、限额、保留期、端点行为、
  `keychain_access_groups` 的授权规则。
- **建议**（你可以改）：轮询节奏、UI 映射、何时用 `standard` 何时用 `split`、adapter 结构、日志策略。

`/v2` 契约变更时，本指南、其英文原文与本包会一起更新，下游项目不需要从实现代码里反推行为。
