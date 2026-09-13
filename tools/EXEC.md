# 执行手册（SOP 的"腿"：工具、截图、清理、补天配方）

> 脑子 = sop/SOP.md（打哪类洞、什么顺序、实锤/判死标准）。
> 本文件 = 怎么落地执行：工具链、cybermes MCP 工具腿、截图配方、补天字段配方、目标清理。
> 旧 bug-bounty-hunting skill 的三块有用部分已吸收进本文件，碎片打法已退役。

## 一、工具链（本机 Windows + git-bash）
- 二进制在项目 `bin/`（自包含）：`ffuf.exe`、`katana.exe`(v1.7)、`nuclei.exe`(v3.11.1)、`httpx.exe`(PD v1.12.0)、`cybermes-mcp.exe`(v3.4.2)
- 用法先铺 PATH：`export PATH="$(cd "$(dirname "$0")/.." && pwd)/bin:$PATH"`；重装见 `tools/install-toolchain.sh`，清单见 `bin/MANIFEST.md`
- subfinder 二进制装不了（GitHub release 国内断流），**走 cybermes 的 crt.sh 引擎兜底**（实测可跑出子域）
- 本机 IPv6 不稳 → 所有 curl 强制 `-4`（阿里 DoH：`https://dns.alidns.com/resolve?name=…`）
- 浏览器 CDP 那条线当前不可用；截图走 Playwright headless（下面第三节）

## 二、cybermes MCP 工具腿（挂到 SOP 阶段）
调用统一走 tool_call，一次一个本地工具（不可混批）。

| SOP 阶段 | cybermes 工具 | 用法 |
|---|---|---|
| 1 资产测绘 | `cybermes_subdomain_discovery` | `prefer_subfinder=false`（走 crt.sh），补 DoH 前缀批量 |
| 2 活体普查 | `cybermes_http_probe` | 每个活子域 1 次，拿 server/cookie/404 指纹 |
| 3 面绘制 | `cybermes_recon_crawl` | katana 爬端点 + JS，`max_endpoints` 控量 |
| 4 洞型-模板 | `cybermes_nuclei_scan` | 非破坏模板扫（exposed-panels/misconfig/cve），`rate_limit` 10 |
| 4 洞型-fuzz | `cybermes_fuzz_endpoints` | 隐藏路径/参数，`status_codes` 带 401/403 抓越权面 |
| 全程 | `cybermes_scan_secrets` | 扫响应/JS 里的凭证 AK/SK（48 模式） |
| 6 报告 | `cybermes_record_finding` / `record_evidence` / `aggregate_report` | 落 journal、聚合 SUMMARY/report.html/PDF |
| 范围核验 | `cybermes_validate_scope` | 每个打之前对 scope.yaml 验目标在范围内 |

注意：本机 cybermes 的"技能库"（`list_skills`/`skills://index`/知识库）是**空的**，别指望它自动给打法——脑子永远是 SOP，cybermes 只提供工具腿 + 报告聚合。

## 三、截图配方（用户负责截图，我负责文字/PoC + 给截图清单）
- **归属证明三张必做**：`1_归属_首页`(官网 logo+厂商名) `2_归属_备案号`(页脚 ICP 原文) `3_归属_证据位置`
- **浏览器截图**（Playwright headless）：`p.chromium.launch(headless=True)`，context 设 UA + `ignore_https_errors=True`；hover 才显示的元素用 `page.evaluate` 强制父级 `display:block`，目标 `a` 加 outline 高亮 + 红色标注 span（写全 URL），`scroll_into_view` 后 `full_page`
- **接口响应截图**（更专业）：不用浏览器，`curl` 拿响应文本，PIL 渲染"终端风格" PNG——黑底 + 等宽字符逐格上色（命令绿 / code:0 绿 / code:-1 或报错红 / HTTP 状态黄），Consolas+雅黑双字体避免中文豆腐块，审核认可度更高
- **验证**：截完 `vision_analyze` 检查目标元素在不在画面里，不在就换子页重截
- **裁剪**：PIL 按高亮色像素 (r>200,g>200,b<150) 定位包围盒，上下扩 150px 裁局部
- 命名固定：`1_归属_首页` `2_归属_证据位置` `3_复现_xxx` …

## 四、补天/盒子字段配方（可复制纯文本，逐字段框起来）
- 逐条给：`等级 / 类型 / URL / 简要描述 / 详细细节 / PoC / 危害 / 修复建议`，用户直接复制
- **详细细节** 4 点：复现过程+影响范围、截图位置、利用组件（无则写"curl 即可"）、PoC
- **PoC 克制**：`sleep 1` 延时、回显 1 行、读 1 行表——不拖全库
- **修复建议** 写可执行操作（加防火墙规则/统一响应/改加密/加鉴权），不写空话
- 归属：公司全称/备案号**逐字核对页脚原文再下笔**，不脑补（曾把"安徽扬子"误成"江苏"被纠）
- 截图必须**本地上传**（点图片图标），复制粘贴图片会被驳回
- 盒子企业项目 → 加 CVSS 向量；补天公益 → 积分制，不夸大严重性

## 五、目标清理（用户规矩）
- 出洞后：报告/PoC/截图已存 `D:\research\journal\<目标>\` 才可删 scratch/Temp；没出洞全删
- 文件名带目标前缀便于 glob；`scratch\<目标>\` 打完即清
- 每打完一个目标必须清理，别漏
- 短命令一律内联跑，别动辄写脚本；被硬拦截才写 .sh 到 Temp 跑完清

## 六、判死速查（证据制，写 journal 后不再磕）
- 未鉴权面全 404/403 + 无弱口令入口 + 无 .git/.bak 可读 → 未鉴权线判死
- 拿不到 2 可用登录态（审核制/滑块/极验）→ 越权/IDOR 线判死
- 自研 WAF 全拦 + 3 种不同绕过手法均拦 → WAF 线判死
- 单 www + 强 WAF + 子域全 404 → 全目标判死（兰大一院型）
- 注册带"提交审核" → 认证型越权线直接判死（万华型）
