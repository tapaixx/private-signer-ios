# v2 契约

PrivateSigner 只维护一个 Worker 契约：`v2`。

## 认证

所有需要认证的 SDK 请求都使用配置中的 `SIGNING_REQUEST_TOKEN` 作为 Bearer token。项目发现、Profile 发现、项目签名和通用 URL/upload 签名不再使用第二套客户端凭据。

## 项目接口

```text
GET /v2/projects
GET /v2/projects/{project_id}
GET /v2/projects/{project_id}/versions
GET /v2/projects/{project_id}/update?current_version=...
GET /v2/profiles?project_id=...
```

项目签名继续使用已有 endpoint：

```text
POST /v2/sign/jobs
```

请求包含 `project_id`、`version_id`、可选 `profile_id` 和签名选项。ProjectVersion 的 source URL、digest 和 expected app version 由 Worker 决定，客户端不能覆盖。

通用 URL/upload 签名继续使用 `/v2/sign/jobs` 与 `/v2/uploads`。

## 服务身份

`GET /health` 不需要认证并声明 `contract: "v2"`。较新的 Worker 还可以返回实现 `version`；客户端不能把 Worker 发布版本号和 API contract 混为一谈。

## Profile ID

Profile ID 是 Worker registry 中的普通运行时数据，由客户端动态发现。任何历史名称都没有协议级 fallback 语义。
