# 判死复审梯子（escalation ladder）—— 判死前的强制动作序列

**定位**：治两个病——①"看个头指纹就判死"（出洞率被自己纪律砍死）②"判死不算数"（用户视角：绕不过去=打法不完整）。
**铁则**：任何格要写 `判死` 之前，按资产形态从 L0 往上爬到能解释当前证据的深度，**每级最多 1-2 发请求（合规封顶不变）**。哪级出了差异响应就下钻哪级，全爬完仍无差异=判死成立，梯级结果写进 deadlines.md 证据（格式：`L0✓ L1✓(路径变体全同墙页) L2✗chunked拦…`）。

## L0 基线重读（0 请求，纯读已有证据）
403 是**墙页**还是**业务页**？（墙页有 data-spm/拦截特征→后面按墙爬；业务页 403→按授权爬，两者绕法不同）
404 是真路由不存在还是 SPA 兜底页？（看字节数是否恒定=兜底）

## L1 路径变体墙（1 发/变体，选 3）
`//admin` `/admin/..;/` `/admin;.js` `/ADMIN` `/%61%64min` `/admin.json` `/admin?.` `/admin/../admin`
原理：网关/WAF/后端三方 URL 归一化不一致，任何一方解析出"同一路径不同判定"=路由差异=面。

## L2 方法/协议变体
HEAD/OPTIONS/POST 代 GET；`X-HTTP-Method-Override`；**HTTP chunked 分块 body**（大量 WAF 不检查 transfer-encoding 分块）；HTTP/2 帧（`curl --http2`，部分 WAF 只解析 1.1 文本）。

## L3 载荷变形（只对注入/参数类，非破坏）
双编码 `%25xx`、参数污染 `?id=1&id=<payload>`、参数挪进 JSON body/multipart、同名参数大小写混用。每型 1 发。

## L4 头伪装与"内网来源"
`X-Forwarded-For: 127.0.0.1` / `X-Real-IP` / `Client-Ip` / `X-Original-URL`。
只证明 403→200 的 diff 即可停（这本身=访问控制缺陷线索），**不借道外挖数据**。

## L5 源站与历史资产
- 盾/WAF 域名 CNAME 链反查真实源 IP：`crt.sh` 历史证书、`securitytrails`/`dnsdump` 历史 A、**App 内置 IP 硬编码**（移动端反编译最肥）、`www` 不同解析。
- 找到疑似源站 → `--resolve host:443:源站` 只测**当初被墙的那个端点**（1 发）。出差异=绕成，后续按源站资产测（授权范围含该 IP 才可）。
- 410/dead 子域 → Wayback 取它活着时的接口路径原样重试（鬼资产：站下线了接口常还在网关活着）。

## L6 "墙后伴生面"（同一入口旁边的门通常没人看管）
actuator 被 WAF 拦 → 试 `/actuator/prometheus`、`/nacos/v1/cs/configs`、`/druid/sql.json`、`/swagger-ui/index.html`、`/knife4j`、`/metrics`（独立前缀常被漏配规则）。
登录墙 → **完整爬登录页 SPA 的 JS**：`guest/preview/public/noAuth/list?` 类未鉴权预览接口是登录站标配；注册页协议链接常指向旧版未纳管子站。
同网关组 → crm 在盾后？同 IP 的 `srm/api/oss` 逐个探（同集群不同 vhost 规则常只配了主域）。

## L7 内网的正确打开方式（公网资产的代理原语）
内网 IP:端口泄露（easthope 型）= 不是去连它（不可路由，物理死路），是把它当**靶标**：
- SSRF 位：`url= redirect= callback= proxy= imageUrl= webhook=`、预览/截图/导入 URL 功能、`file=http://内网/`
- 回显内网数据/元数据（169.254.169.254 或内网服务 banner 出现在响应里）= **高危实锤**（入口是公网授权资产，合法）
- gopher/JNDI 高级玩法超出克制原则不做；证明到"能替我请求"即停。

## 封顶与豁免（合规不变量）
每级 1-2 发、全梯 ≤15 发/面、不爆破不字典不 DoS。L1-L7 爬完无差异=判死成立可写证据；
只有全站 403 盾页（任何路径任何方法都同页同字节）可从 L1 快进到 L5（源站是唯一活路），豁免要写明跳级理由。
**墙页 ≠ 证据穷尽。"我试了被 WAF 拦"不写判死，要写"梯 L1-L4 各 1 发均返回同一墙页(字节相同 hash=xxxx)"。**
