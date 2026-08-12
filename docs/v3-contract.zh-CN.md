# PrivateSigner v3 客户端契约

v3 是一次破坏性的 bug 修复协议。SDK 不再自己发现 GitHub Release，也不再内置 provisioning profile ID。

## 项目自更新

宿主 App 只编译一个稳定的 `projectID`。流程：

1. `GET /v3/projects/{projectID}/update?current_version=...`
2. 使用 Worker 返回的默认可签 profile，或从返回列表中选择另一个 profile
3. `POST /v3/sign/jobs`，只提交 `project_id`、`version_id` 和签名行为参数
4. 轮询 `/v3/sign/jobs/{jobID}`，完成后获取 delivery links

项目模式中 SDK 不会得到、也不会提交 unsigned IPA URL。源 URL、源 digest、预期版本都是 Worker 的 ProjectVersion 事实。

## 通用签名

URL 和本地 IPA 签名继续通过 `createURLJob` / `uploadAndCreateJob` 提供，但 Principal 必须具有 `generic-url-sign` / `upload-sign` scope。Profile 通过 `GET /v3/profiles` 发现，不再把 profile ID 当作自由文本配置。

## 删除的 v2 假设

- `/v2` 客户端路由不再支持
- `personal-main` 不再有任何特殊含义
- 删除 `GitHubReleaseSource`
- 删除 `SignerUIContext.defaultProfileID`
- `SelfUpdateCoordinator` 和 `SelfUpdateView` 改为接收 `projectID`
