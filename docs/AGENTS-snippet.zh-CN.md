# AGENTS.md 片段

[English](AGENTS-snippet.md) · **简体中文**

接入完成后，把下面这段粘进项目的 `AGENTS.md` / `CLAUDE.md`。它写的是**后来的 agent 需要知道
什么才不会把接入搞坏**——不是功能说明。

```markdown
## 私有 IPA 签名

本项目通过 `private-signer-ios` 包，向 Private IPA Signer 部署请求签名。接入指南：
https://github.com/nnnmdzz/private-signer-ios/blob/main/docs/client-integration-guide.zh-CN.md

- 所有应用特定的签名配置只放在 `<path>/PrivateSigningAdapter.swift`。
  `SignerKeychainConfiguration` 和 `GitHubReleaseSource` 只在那里构造，别处一律不构造。
- Worker 地址和 Signing Request Token 是**用户配置**，存在 Keychain 里。
  绝不要把它们写进源码、构建设置、plist、测试、日志或提交信息。
- `configurationAccessGroup` 是 Stable Configuration Group。**改掉它的值会让所有已安装客户端
  的配置成为孤儿**。要换的话，把旧值加进 `legacyAccessGroups`，而不是替换。
- 每个签名请求都必须带上 `store.authorizedAccessGroups`。`SelfUpdateCoordinator` 会自动带；
  直接调 `SigningClient` 时要自己传。
- `requestSignedBuild` 必须显式传 `target:`。`.installedApp` 是升级，`.sideBySideClone` 是
  多装一个 App。**不要让这个选择变成隐式的。**
- 分支要用错误的 `code` 属性，展示用 `errorDescription`。**永远不要解析文案。**
- 依赖用 `exact:` 锁死，不要放宽成范围。
- **CI 无法验证签名产物能否装到真机上。** 没有人按指南 §7 的真机清单跑过之前，
  不要把签名相关改动汇报为"已验证"。
```

## 为什么是这些条目

每一条都对应一种**失败得很晚、很难查**的错误：

| 条目 | 违反后会发生什么 |
|---|---|
| 配置集中在 adapter | 应用特定值散落各处，升级包时要改十个地方 |
| 不写死凭据 | 公开仓库泄露完整签名权限 |
| 不改 access group | 用户下次自更新后，配置消失、要重输看不见的 token |
| 带上 access groups | 签出来的 App 读不到自己的配置 |
| 显式 target | 桌面上多出一个图标，而用户以为更新成功了 |
| 用 code 分支 | 换了语言或改了文案，错误处理静默失效 |
| exact 锁版本 | 自更新链路被依赖漂移弄坏，而它正是修复的通道 |
| 真机验收 | `codesign` 通过不代表 iOS 装得上 |
