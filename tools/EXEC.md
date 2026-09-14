# 执行手册（SOP 的"腿"：工具、截图、清理、补天配方）

> 脑子 = sop/PLAYBOOK.md（简版 SOP.md；打哪类洞、什么顺序、实锤/判死标准）。
> 本文件 = 怎么落地执行：工具链（全自有 bin/ + 自研 tools/）、截图配方、补天字段配方、目标清理。
> 无任何第三方 MCP 依赖，全流程走项目自研 `tools/hunter-cli.sh` 编排 + `bin/` 底层引擎。

## 一、工具链（本机 Windows + git-bash）
- 二进制在项目 `bin/`（自包含，第三方底层引擎）：`ffuf.exe`(v2.1)、`katana.exe`(v1.7)、`nuclei.exe`(v3.11.1)、`httpx.exe`(PD v1.12.0)
- 自研工具在 `tools/`（脑子腿）：`hunter-cli.sh`（subs/recon/probe/matrix/monitor 纯自研）、`mailacct.py`（合规双邮箱）、`xssprobe.py`（Playwright 三态判定）、`apksecret.py`（apk 密钥扫描，零 Java）
- 用法先铺 PATH：`export PATH="$(cd "$(dirname "$0")/.." && pwd)/bin:$PATH"`；重装见 `tools/install-toolchain.sh`，清单见 `bin/MANIFEST.md`
- subfinder 二进制装不了（GitHub release 国内断流），**走 `hunter-cli subs` 的阿里 DoH + crt.sh 自研引擎补长尾**（实测可跑出子域）
- 本机 IPv6 不稳 → 所有 curl 强制 `-4`（阿里 DoH：`https://dns.alidns.com/resolve?name=…`）
- 浏览器存储 XSS 走 `tools/xssprobe.py`（Playwright headless 三态判定 A/B/C，见第三节）

## 二、自有工具腿（挂到 SOP 阶段，全自研无第三方 MCP）
编排统一走 `tools/hunter-cli.sh`（子命令见其 help），底层引擎在 `bin/`。

| SOP 阶段 | 自有腿 | 用法 |
|---|---|---|
| 1 资产测绘 | `hunter-cli subs` | 阿里 DoH 批量 200 前缀（并行 xargs-P20）+ crt.sh，补长尾子域 |
| 1+2 一键 | `hunter-cli recon` | subs + 官网扫 + 活体普查一条龙（产物落 HUNTER_SCRATCH/<slug>/） |
| 2 活体普查 | `hunter-cli probe` | 每个活子域 1 次，纯 curl 拿 server/cookie/404/WAF 指纹（https死回退http） |
| 2 活体普查 | `hunter-cli scan` | 调 `bin/nuclei.exe` 非破坏模板扫，`bin/templates/` 本地库，限速 10 |
| 3 面绘制 | `hunter-cli crawl` | 调 `bin/katana.exe` 爬端点+JS，`-ct` 控量 |
| 4 洞型-fuzz | `hunter-cli fuzz` | 调 `bin/ffuf.exe` 隐藏路径/参数，限速、带 401/403 抓越权面 |
| 4 开工 | `hunter-cli matrix` | 攻击面矩阵骨架（A1-A9×资产，三终态制：实锤/已试/判死） |
| 持续侦察 | `hunter-cli monitor` | 子域快照 diff，报新增（忘下线旧站）/鬼资产 |
| 4 存储 XSS | `tools/xssprobe.py` | Playwright 元素级 canary 判 A/B/C，`--then` 走多步 client-side 流 |
| 越权双账号 | `tools/mailacct.py` | 邮箱双号（收件侧），手机号用户侧 |
| A' 移动端 | `tools/apksecret.py` | apk/解包目录 扫硬编码密钥+API基址（纯 stdlib 零 Java） |
| 6 报告 | 人工整理 | 骨架见 `templates/finding-poc.md`，补天/盒子字段见第四节 |

注意：第三方引擎（nuclei/ffuf/katana/httpx）只作为 `bin/` 底层依赖被调用，不对外冒头；第三方 MCP 无依赖，全流程走项目自研 `tools/` + 引擎——脑子永远是 `sop/PLAYBOOK.md`（简版 `sop/SOP.md`，`hunter_brain` 按需取）。

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
