# Private Signer iOS Client

[English](CONTEXT.md) · **简体中文**

本文描述私有 IPA 签名的客户端一半：一个 App 如何请求签名、如何证明拿回来的就是它要的那个、以及如何安装它。

本文是 [CONTEXT.md](CONTEXT.md) 的翻译。**冲突时以英文版为准**——术语的唯一定义在英文侧，
而服务端一侧的术语是**逐字复述**而非链接（那个仓库是私有的，这个不是）。某个术语变化时，两侧要一起改。

## 术语

### 客户端概念

**Signer Client**：
代表一个已安装应用提交签名请求并跟踪其任务的库，自身不持有任何签名权限。
_避免_：签名 SDK、API 封装、signer

**Integration Adapter**：
宿主应用内部那一小段代码，负责把应用特定的值——发布仓库、附件名、access group、user agent——
交给一个本身与应用无关的 Signer Client。
_避免_：配置文件、胶水代码、桥接层

**Release Source**：
客户端发现自身新版本的应用特定方式，也是自更新流程中**唯一**因项目而异的部分。
_避免_：更新源、版本检查器、版本 API

**Self-Update Coordinator**：
把发现到的 Release Candidate 变成可安装 Signed Artifact 的客户端流程，方式是发起一个普通的签名请求。
_避免_：更新器、自动更新服务、OTA 管理器

**Release Candidate**：
一个被发现的、客户端可以安装的构建，携带版本号、可重签 IPA 的地址，以及一个可选的摘要
（把请求绑定到确切的字节）。
_避免_：最新版本、新版本、更新

**In-Place Update**：
Target Bundle ID 等于已安装应用身份的签名请求，因此 iOS 会**替换**正在运行的 App 而不是再装一个。
_避免_：普通更新、自更新、升级

**Side-by-Side Clone**：
Target Bundle ID 有意不同于已安装应用身份的签名请求，因此签出来的构建会**并排安装**，
原来那个继续存在。
_避免_：多实例、多开、第二份

**Stable Configuration Group**：
在未来每一次签名之后仍然持有该应用 Worker 地址与 Signing Request Token 的 Keychain access group。
必须显式指定，因为默认组由 provisioning profile 推导，profile 一变它就变。
_避免_：默认 Keychain 组、当前 access group、app group

**Signing Environment**：
一组具名的已存 Signer 凭据，让一个已安装应用同时持有生产与测试两套配置而不必来回重输。
_避免_：profile、工作区、账号

**Signature Renewal**：
因为签名即将过期而**重新签同一个版本**，区别于安装一个更新的版本。刻意与 In-Place Update 分开：
调用方把"发现到候选"读作"有更新的版本"这件事必须一直成立。
_避免_：刷新、重签、更新

**Installed Signature**：
运行中应用自己的 `embedded.mobileprovision` 所陈述的事实：签名何时过期、由哪个 profile 产生、
以及那个 profile 是不是 Apple 签发的 7 天期免费账号 profile。
_避免_：描述文件信息、证书有效期、profile

**Service Contract**：
一个 Signer 部署在其**免鉴权**健康端点上声明的接口版本，用来在发送 token 之前区分
"这个地址不是 Signer"和"这个 token 不对"。
_避免_：API 版本、健康检查、ping

### 服务端概念（逐字复述自 Private IPA Signer 的术语表）

**Signing Request**：
一条经过鉴权的指令，要求获取一个 Resignable IPA 并用显式的签名选项产出一个绑定设备的签名产物。
_避免_：更新请求、发布请求、队列项

**Signing Job**：
由一个被接受的 Signing Request 创建、拥有唯一标识、由调用方轮询直到签名成功或失败的执行过程。
_避免_：工作流运行、R2 记录、构建

**Signing Request Token**：
其持有者拥有完整权限、可从 App、快捷指令或命令行客户端提交 Signing Request 的 bearer 凭据。
_避免_：Personal Update Token、管理员 token、应用 token

**Resignable IPA**：
可执行代码未被 FairPlay 加密、因而无需解密即可获得新的有效代码签名的 IPA。
_避免_：已解密 IPA、破解 IPA、未签名 IPA

**Source IPA**：
被一个 Signing Request 选作输入产物的可重签打包应用，无论它此前是否已签名。
_避免_：发布附件、更新包

**Upload Session**：
经过鉴权、可续传的序列，把一个设备端选择的 IPA 由有界分片组装起来，随后成为 Source Snapshot。
_避免_：分片上传、临时对象、上传任务

**Source Snapshot**：
Source IPA 首次成功下载时创建的不可变副本，以其 SHA-256 摘要标识。
_避免_：下载缓存、临时 IPA、来源 URL

**Signed Artifact**：
由一次成功的 Signing Job 产出、其保留期独立于可续期短时下载链接的绑定设备 IPA。
_避免_：结果 URL、manifest、签名更新

**Delivery Link**：
可续期、用途绑定的 URL，在其短暂有效期内可重复访问一份 manifest 或一个 Signed Artifact。
_避免_：下载 token、永久链接、产物 URL

**Target Bundle ID**：
签名后主 App 的可选请求身份；省略时保留 Source IPA 的主 bundle 标识。
_避免_：Bundle ID 覆盖、克隆 ID、请求的 bundle ID

**Requested Keychain Groups**：
Signing Request 要求签名器在所选 provisioning profile 的授权范围内保留或物化的一组
Keychain access group。
_避免_：split 访问组、Keychain 权限覆盖

**Profile ID**：
选中一套已配置证书与 provisioning profile 集合的稳定、非机密别名；省略时选中显式默认值。
_避免_：profile 槽位、证书名、签名身份

**Device Gate**：
服务端强制的要求：某个 Profile ID 的 provisioning profile 必须覆盖已配置的目标设备，
**不受调用方输入影响**。
_避免_：UDID 列表、允许设备、设备过滤

**Profile Set**：
共同为一个 root App 及其嵌套包签名的一组 provisioning profile，由 Profile ID 作为整体选中，
也是 Device Gate 唯一的推导范围。
_避免_：profile 分组、profile 包、证书 profile

**Signing Mode**：
一个 Signing Job 的显式身份策略：Standard 让 bundle 身份与 application 身份按常规对齐，
Split 让最终 bundle 身份与 profile 推导出的 application 身份保持分离。
_避免_：签名策略、改写模式、身份模式

**Embedded Bundle Policy**：
对所选 Profile ID 无法签名的扩展、小组件、Watch App 及其他嵌套包的处理要求：移除并报告，
或要求全部保留。
_避免_：插件处理、扩展清理、嵌套签名模式

**Entitlement Policy**：
对所选 provisioning profile 未授权的来源能力的处理要求：移除并报告，或要求全部保留。
_避免_：能力清理、权限过滤、权限模式
