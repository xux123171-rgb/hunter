
# hunter — 全谱系挖洞流程（严重→低 · 零落地 · 证据制判死）

用户：小徐（非技术背景，我操盘他提交）。合规授权范围内测试。
项目根：clone 到的仓库根（`server.py` 从 `__file__` 自发现，不设也能跑）——SOP.md=脑子，tools/EXEC.md=腿，bin/=工具，journal/=归档，scratch/=工作产物。

## 铁律（每次先默念）
1. **零落地**：只看响应头/状态码/字节数/前几百字节，不下全量 JS/大文件。大文件只 `-r 0-2048` 验可下载。
2. **实锤才算洞**：数据真泄露/真越权/真 RCE/真读文件。500 报错、返回 success、WAF 拦截页 = 不算。
3. **判死证据制**：判死必须写证据进 journal，不靠"经验"。不磕已判死的线。
4. **payload 克制**：sleep 1 / 回显 1 行 / 读 1 行表。不拖全库、不写破坏性 payload。
5. **归属逐字**：公司全称/备案号逐字核对页脚 ICP 原文再下笔，不脑补。
6. **合规硬限**：手动 ≤2 req/s/host，fuzz/扫描需放行；证明影响用"读"不外泄、PII 只留首行打码；不落点不横移；zero-destroy。

## 6 阶段（每个目标从头走完，不预设打法）
### 阶段-1 目标挑分（先筛后打；挑分理由写 journal）
值得打：①前端泄露内网IP:端口 且 同资产有公网可达管理面（hb2h 型，出洞率最高）②老系统无 WAF 遗留站（IIS+WebForms/老 Tomcat/e-cology6/DedeCMS）③业务子域多的大厂（open/api/app/m 逐个探）④SPA 集团站（前端 config 必挖域）。
快判死别磕：①单 www+强 WAF（兰大一院型）②注册带"提交审核/耐心等待"→认证型 IDOR 线直接死（万华/极验/齐治型：无 token=无洞）③邮箱/网盘全在第三方 SaaS（洞在厂商侧）。
WAF 速认：acw_tc+ALIWAF_CACHE=阿里云WAF；yundunwaf*=阿里盾；510+"触发WAF防护:xxxx"=自研引擎（ROI 最低）；CT2-WAAP=雷池。
### 阶段0 范围红线（人工填 scope.md）
授权范围逐字抄、奖励类型(现金/积分)、定级标准、限额(越权读≤N组/注入只证可读)。判死前置信号：注册带"提交审核"→IDOR 线标黄；无登录态入口→认证型线标黄。

### 阶段1 资产测绘（自动：`bash tools/hunt.sh <domain> [slug]`）
- 子域：DoH 批量 200 前缀 + crt.sh（`bash tools/hunter-cli.sh subs <domain>`，自研逻辑走阿里 DoH + crt.sh，无第三方依赖）。本机 IPv6 不稳→所有 curl 加 `-4`，DNS 走阿里 DoH `dns.alidns.com/resolve`。
- 官网源码扫：内网 IP:端口、第三方 SaaS 域、JS 引用、备案原文。
- **关键判定点**：有"内网 IP:端口 且公网可达"的行 → 直进阶段2深打通道（hb2h 型，出洞率最高）。

### 阶段2 活体普查（自动 + nuclei）
每活资产 1 次拿 status/Server/Set-Cookie/404指纹/WAF指纹。指纹→洞型映射：
- IIS+WebForms+Oracle → 未鉴权 ashx 接口、sqlId 白名单枚举（hb2h 型）
- Tomcat 老版 → manager 弱口令/Jasper
- Exchange → 三连判死（DesiredUser→401、裸GET→401空、OWA SSRF 试 169.254）
- 泛微 e-cology → /weaver/* 全500无堆栈 + /api/ec/v1 全404 = 判死
- nginx 裸 welcome 页 = 死；自研 WAF（510+"触发WAF防护"）= 有墙
nuclei 非破坏扫：`bin/nuclei.exe -u <活资产URL> -t "bin/templates/http/misconfiguration" -severity critical,high -rl 10`（模板已本地化到 `bin/templates/`，国内不再联网拉）。

### 阶段3 面绘制（katana 爬）
端点 × 前置(cookie/签名) × 参数矩阵。JS 只下 <200KB：提 API host、AK/SK（前端公共 key 不当洞）、内网 IP、隐藏路由。每端点 1 次最小请求定性。记 scratch/endpoints.md。

### 阶段4 洞型测试（Agent 判断，严格 严重→低，出实锤即停该型）
**影响按最远可达点定级**（primitive→impact 链，入口只决定能不能进，不决定值多少）。对每端点先发散假设，试出 primitive（可控原语），再推到最坏 impact。
**严重**：RCE/命令注入（延时回显）· SQL 拖库（真读表/列）· 未鉴权数据接口（字节级 diff 证全量）· SSRF→169.254.169.254 · 反序列化（aced0005/rO0AB 首字节）· 文件上传（canary 可回读/执行）
**高**：IDOR/BOLA（需≥2可用账号，邮箱走 `tools/mailacct.py`）· 垂直越权 · 认证绕过（alg:none/空token）· 业务逻辑 · race/并发（WAF 盲区，最高性价比）
**中**：存储 XSS（`tools/xssprobe.py` 元素级 canary 判 A/B/C）· 用户名枚举 · 信息泄露链（.git/.bak/.map/actuator）
**低**（凑报告厚度不单报）：开放重定向 / 缺安全头 / 版本泄露 / 默认 404 框架名 / cookie 缺 Secure/HttpOnly
**强防护打法**（WAF/CDN 有墙时）：按 `references/waf-bypass.md` 先试「CDN 源站直连 + 业务逻辑面（WAF 盲区）」，别硬刚 WAF；race/业务逻辑见 `references/race-business-logic.md`（并发 2~5 个克制、不轰炸）
每型三要素：探测法→实锤标准→判死标准。出实锤记 `reports/<slug>/finding_<n>.md`，判死记 `scratch/<slug>/deadlines.md`。

### 阶段5 实锤复核（先 FP-elimination 再 7 问，任一不过降级或砍）
**5a FP-elimination（攻击性排误报）**：① 追入口→sink 全路径，标每个 校验/过滤/WAF 点；② 每个防御点都要过掉才算，任一处挡住→降"被缓解"；③ 对照组硬要求：合法值 vs payload 响应必须 diff 出差异，无差异=误报；④ 区分"设计如此"（CDN 缓存/公开素材//plugins 返 401）；⑤ 激进重估：假设它是误报，自证不了就砍。
**5b 7 问**：① 可复现？② 真影响非报错？③ 归属三截图齐？④ 在范围内？⑤ 没踩红线/PII 打码？⑥ 定级按最远可达点对？⑦ 做了对照组？

### 阶段6 报告（可复制纯文本 + 结构化 finding）
- 工作区 `reports/<slug>/{SUMMARY.md,metadata.json,findings/,pocs/,evidence/recon_notes.md}`；findings/ 只放已确认洞（snake_case 无方括号），INFO/缺头/版本泄露/阴性测试归 evidence/recon_notes.md；每洞配 pocs/poc_<name>.py（骨架见 templates/finding-poc.md）。
- 出完人工整理 SUMMARY.md/metadata.json（自研 aggregate，无第三方依赖）。
- 每洞三块可复制纯文本：简要描述 / 详细细节（归属链+具体影响场景）/ PoC。补天=积分；盒子=现金加 CVSS。截图清单逐张命名（用户拍，本地上传勿粘贴）。

## 阶段门（进下一阶段的前置条件，不过就停+写 journal）
0→1 有 scope 逐字+红线；1→2 有 ≥1 活资产；2→3 有 ≥1 活且有面资产；3→4 有 ≥1 可枚举/无鉴权端点；4→5 finding 有 raw 证据；5→6 7问+FP-elimination 全过。

## 自有工具腿（脑子是 SOP，tools/ 全自研，无第三方 MCP 依赖）
`tools/hunter-cli.sh` 自研编排：`subs`（子域，DoH+crt.sh）· `probe`（活体指纹，纯 curl）——第三方引擎（nuclei/ffuf/katana/httpx）只作为底层依赖被调用，不对外冒头。

## 影响/优先级/合规 参考
`references/impact-priority-gates.md`（影响框架、哪类洞真给钱、合规硬限、divergent→primitive→impact、FP-elimination、阶段门、**七·合规深度封顶表**：每洞型打到哪算封顶/绝不碰）。另 `waf-bypass.md`（强防护打法）、`race-business-logic.md`（业务逻辑+并发）。

## 工具链（项目 bin/，全部验证可跑）
`bin/`：ffuf.exe(v2.1) / katana.exe(v1.7) / nuclei.exe(v3.11.1) / httpx.exe(PD v1.12，**非** Python httpx 包) + `bin/templates/`(nuclei 模板本地库)。清单+重装脚本见 `bin/MANIFEST.md` 与 `tools/install-toolchain.sh`（**含 nuclei 模板本地化 download_templates**）。
自有工具（tools/）：`hunter-cli.sh`（subs/probe 自研腿）、`mailacct.py`（合规双邮箱，收件侧实测）、`xssprobe.py`（Playwright 三态判定，A/B/C 实测）、`install-toolchain.sh`、`push-to-github.sh`。
铺进 PATH：`export PATH="$(pwd)/bin:$PATH"`（在项目根）。Playwright 需用 Hermes venv python：`C:/Users/ThinkPad/AppData/Local/hermes/hermes-agent/venv/Scripts/python.exe`。

## 截图配方（用户拍，我给清单）
归属证明三张必做：`1_归属_首页`(logo+厂商名) `2_归属_备案号`(页脚ICP原文) `3_归属_证据位置`。
浏览器=Playwright headless(UA+ignore_https_errors)；接口响应=PIL 终端风格 PNG(黑底+等宽逐格上色，Consolas+雅黑双字体防豆腐块)；截完 vision_analyze 验目标在画面里。

## 目标清理（每打完必须清）
出洞后：报告/PoC/截图已存 `D:\research\journal\<目标>\` 才可删 scratch/Temp；没出洞全删。文件名带目标前缀便 glob。

## 判死速查（写 journal 后不再磕）
未鉴权面全404/403+无弱口令入口+无.git/.bak可读→未鉴权线判死 · 拿不到2可用登录态→越权/IDOR线判死 · 自研WAF全拦+3种绕过均拦→WAF线判死 · 单www+强WAF+子域全404→全目标判死（兰大一院型）· 注册带"提交审核"→认证型越权线判死（万华型）。

## 攻击面全覆盖矩阵（授权内可打的全部写死在这；一项不通接下一项；矩阵清空=打完）
### A. 可打面总清单（阶段1/3 多渠道扩资产，漏一面=漏一洞）
1. **公网子域**：DoH 词表爆破 + crt.sh CT + **前端配置/JS 挖域**（`config/index.js`、webpack chunk 写死的 API 域是最准的子域来源——easthope 实战：200 前缀词表漏掉的 3 个后端子域全靠 wms 的 config/index.js 救回）+ Wayback 历史 URL + GitHub 组织公开仓库代码 + App/小程序解包配置 + ICP 主体反查姊妹域名
2. **公网 IP 资产**：每条活 A 记录都探可达（含非标端口几百字实验证）
3. **CDN/WAF 源站**：dig 多时点跳变 + crt.sh 历史 IP + App 内置 IP → `--resolve` 直连绕边缘
4. **框架自带管理面**：actuator / swagger·knife4j / druid / nacos / dubbo-admin / tomcat manager / heapdump / .env…（有墙时按 waf-bypass.md 三手法）
5. **泄露文件**：.git/.svn/.env/.bak/.sql/备份包/web.config（ffuf 词表 fuzz）
6. **认证流程面**：注册/登录/找回密码/验证码/SSO·OAuth 流/单点票据（用户名枚举、认证绕过、弱口令入口探测=授权内克制尝试，禁字典轰炸）
7. **业务接口面**：未鉴权 API 直读（字节级 diff 证真实影响）+ 登录态后 IDOR/越权（双账号法，邮箱走 `tools/mailacct.py`）
8. **输入回显面**：注入点（SQLi 延时/命令回显/SSRF→169.254）+ 上传点（canary 回读）+ 存储 XSS 回显位（xssprobe 三态）
9. **第三方集成密钥**：前端公共 key 不算洞；**私有** AK/SK、硬编码凭证泄露=实锤可报
### B. 红线（平台授权也不打）
内网段（127./10./172.16-31./192.168. 不可路由不探不报拖）、横向移动/跳板、拖全库、DoS/并发轰炸、社工钓鱼、任何破坏性写入。授权边界只到公网资产。
### C. 洞型矩阵状态机（强制，防"看指纹就收工"）
阶段4 一开工就在 `scratch/<slug>/matrix.md` 建矩阵：**行=上面 A 的每个可打面 × 阶段4 洞型（严重→低），列=每个活资产**。每格状态只有三种终态：
- `实锤` → 记 finding，该型停
- `已试（记录请求数+响应特征）` → 接下一行
- `判死（写证据编号进 deadlines.md）` → 接下一行
**一项不通立刻接下一项，不许磕；矩阵所有格到终态之前，该目标无权宣布"打完"。**
**最低深度门槛（判死前置，缺一不许写判死）**：每个被判死的活资产必须先跑完"最低三件套"——① `hunter_scan`（nuclei 本地库非破坏模板）② `hunter_fuzz`（ffuf 关键路径，限速5）③ `hunter_crawl`（katana depth2 + -jc JS 挖）。豁免唯一形式=证据制写明（例："全站 403+盾页，三件套只会撞墙，头证据见 deadlines#3"），且豁免理由必须可被用户拿请求数复核。
> 复盘教训（easthope）：本轮只靠响应头指纹判死，三件套一件没跑——按新规则属于"没打完"，下次目标起强制执行。

---
<!-- 同步源: Hermes 已安装 skill 为 skills/hunter/SKILL.md（本文件是其正文副本，去掉 frontmatter）。
     改 SOP/打法时两边都更新；MCP hunter_brain(what=playbook) 读的就是这份，保证 MCP 自包含可移植。 -->
