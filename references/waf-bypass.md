# WAF 绕过（合规）—— 我们的参考

**定位**：阶段 2 指纹出"有墙"后、阶段 4 打洞前，判断"绕还是判死"。合规红线：payload 克制、不 DoS、不暴力爆破、不横向——绕过只为**验证洞**，不为破坏。

## 0. 先判该不该绕（判死纪律，写在 journal 再动手）
- 自研 WAF（`510 + "触发WAF防护:xxxx"`）→ 全拦且规则定制，ROI 最低，**通常判死**。
- 通用 WAF（Cloudflare/Akamai/某 CDN）→ 常有**源站**可绕过，值得试。
- 铁律：**3 种不同手法都拦 → 该面判死**，不磕。

## 0.5 401/403 绕过字典（测管理/接口面的固定动作，≤3 手法再谈判死）
- **路径变体**：`/admin/` `//admin` `/admin;.js` `/admin/..;/`（Spring/网关归一化差异）`/ADMIN` `/adMin` `/%61%64min` `/admin.json` `/admin?.`
- **头伪造**：`X-Original-URL: /admin` / `X-Rewrite-URL:`（老 IIS/Spring 坑）；`X-Forwarded-For: 127.0.0.1` / `X-Real-IP` / `Client-Ip`（内网来源伪装——只证 403→200 diff，不外挖数据）
- **方法变体**：POST/HEAD/OPTIONS 代 GET、`X-HTTP-Method-Override: GET`、`_method=GET`
- **编码变体**：URL 二次编码、Unicode 同形、`%00` 尾
- 实锤标准：绕过后与同 URL 的 403 基线**字节级 diff**；WAF 拦截页 ≠ 业务 403——拿墙页当"绕过了"的证据是 FP。

## 1. 源站直连（CDN/WAF 绕过主力）
通用 CDN 只挡 CDN 边缘，源站往往裸奔：
1. 找源站 IP：`dig +short` 多时点抓 A 记录跳变 / `hunter-cli subs` 里的 IP 里挑非 CDN 段 / 历史 DNS（crt.sh 证书 IP）/ 移动端 App 包里的 IP。
2. 直连绕过 CDN：
   ```
   curl -sk4 --resolve host:443:<源站IP> https://host/...   # 只认源站，绕过 CDN WAF
   ```
   或用 `Host: host` 头 + 直连源站 IP。**CDN 的 WAF 规则在源站不存在**——这条是"有墙也能打"的核心。
3. 实锤标准：源站返回与 CDN 不同（放行/回显），且确认**打的是授权范围内资产**。

## 2. payload 混淆（绕过签名/关键词检测）
- **双编码**：`%25xx`（编码两次）让 WAF 解一层看到无害、后端解两层看到 payload。
- **body 携带**：WAF 重点查 URL/query，把参数挪进 POST body / JSON 里，检测松。
- **HTTP/2 vs 1.1**：部分 WAF 只解析 HTTP/1.1 文本，打 `--http2` 走二进制分帧，绕过文本规则。
- **参数污染 HPP**：`?id=1&id=<payload>`，WAF 与后端取参不同。
- 克制：每手法 1 次验证，不组合轰炸。

## 3. 业务逻辑面 = WAF 盲区（最高性价比）
WAF 只认"已知恶意 payload 特征"，**认不出业务逻辑**：改订单金额、跳步骤、并发越权、改角色位。这类**根本不需要"绕过 WAF"**——WAF 对逻辑洞是 100% 瞎的。强防护目标最该打的就是这条线。

## 4. 厂商特定
自研 WAF 有规则号（`120002` 型）→ 查其厂商公开绕过写进 journal，针对性 1 次，不命中即判死。

## 判死速记
`CDN 源站可绕 + 逻辑面未试` → 可继续；
`自研 WAF 全拦 + 源站同源 CDN + 逻辑面已试` → 判死。
