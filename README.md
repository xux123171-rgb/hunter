# hunter — 合规 Web 漏洞挖掘流水线

一套**全谱系、严重→低危、零落地**的 Web 漏洞挖掘方法论 + 自动化工具链。
核心思想：**脑子是 SOP（打哪类洞、什么顺序、实锤/判死标准），腿是 11 条自研工具（hunter-cli 编排 + ffuf/katana/nuclei/httpx 底层引擎 + 自研 python 工具）**。
不靠"经验型"预设打法——每个目标从头走完阶段流程，出洞按实锤判定，判死按证据判定。

> 仅用于**授权范围内**的安全测试（SRC/补天/漏洞盒子等）。默认合规：注入只证可读、payload 克制（sleep 1/回显/读 1 行）、越权读限额、禁扫描器/社工/内网渗透/DDoS。

## ⚠️ 法律免责声明（Legal Disclaimer）

本项目仅用于**教育目的**与**授权安全测试**。你只能对以下目标使用本工具：

* 你自己拥有或运营的资产；
* 漏洞赏金/SRC 项目（补天、漏洞盒子、HackerOne 等）**明文允许**的资产范围；
* 你持有**书面授权**的测试对象。

❌ **严禁**对未授权的任意域名/基础设施扫描或测试。未授权访问计算机信息系统在中国及多数司法辖区构成刑事犯罪。
作者不对使用本软件造成的任何后果负责。使用即视为你已理解并承诺遵守上述边界。

## 目录
```
hunter/
├── sop/
│   ├── PLAYBOOK.md           # 脑子主文档：阶段-1挑分→6报告 + 攻击面矩阵A1-A9 + 判死梯子 + 实战教训
│   └── SOP.md                # 简版速览
├── references/               # 方法论扩展
│   ├── impact-priority-gates.md    # 影响框架/合规硬限/FP排除/阶段门/合规深度封顶表
│   ├── waf-bypass.md               # 强防护合规绕过（源站直连/401绕过字典/混淆/逻辑面）
│   ├── death-escalation-ladder.md  # 判死复审梯子 L0-L7（判死前强制爬，"被WAF拦"≠证据穷尽）
│   └── race-business-logic.md      # 业务逻辑 + 并发 race（WAF 盲区；barrier 齐射纪律）
├── tools/
│   ├── EXEC.md           # 腿：工具链速查、截图配方、补天字段、清理、判死速查
│   ├── hunter-cli.sh     # 统一入口：subs/recon/probe/crawl/scan/fuzz/matrix/monitor/report
│   ├── hunt.sh           # 一键跑 阶段-0~3（自动部分），把面摊开给 Agent
│   ├── hunt-recon.sh     # 阶段1+2：子域枚举(并行DoH+crt.sh) + 官网扫 + 活体指纹普查
│   ├── mailacct.py       # 合规双邮箱账号（越权双号，mail.tm 收件侧：create/inbox/otp）
│   ├── xssprobe.py       # 存储XSS 三态判定（Playwright 元素级 canary，--then 支持多步client-side流）
│   ├── apksecret.py      # 移动端线：apk/解包目录 扫硬编码密钥+API基址（纯 stdlib 零 Java）
│   ├── test.sh           # 离线回归总入口（30秒零真实请求，红绿门禁）
│   ├── install-toolchain.sh  # 可复现重建 4 引擎 + nuclei 模板本地库
│   ├── install-hermes.sh     # 换机一键：venv + skill + MCP 注册（缺啥补啥幂等）
│   ├── push-release.sh / push-to-github.sh   # 两级发行包维护 / 推送
│   └── wordlists/common.txt  # ffuf 隐藏路径/泄露类小词表
├── bin/                    # 底层引擎（第三方，gitignore 挡出 git，靠 install 重建）
│   ├── ffuf.exe katana.exe nuclei.exe httpx.exe
│   ├── templates/         # nuclei 模板本地库（~11k http，只留本地）
│   └── MANIFEST.md + VENDOR.md
├── templates/
│   ├── finding-poc.md       # finding + PoC 骨架
│   └── report-btt-vulbox.md # 补天/盒子可复制报告模板
├── mcp/                     # 我们自己的 MCP 服务（FastMCP stdio，11 工具全自研）
│   ├── server.py            # recon/probe/crawl/scan/fuzz/matrix/monitor/xss/accounts/apk/brain
│   └── full_test.py         # 11工具离线/在线复测（防回归门禁）
├── LICENSE                  # MIT
├── CONTRIBUTING.md          # 入伙规矩：回归必绿/禁提交目标数据/合规红线拒收
├── journal/<目标>/          # 出洞归档：scope/report/finding/截图清单（gitignore）
├── scratch/<目标>/          # 工作产物：assets/probe/endpoints/matrix/deadlines，打完即删（gitignore）
└── reports/<目标>/          # 报告 + 证据（gitignore）
```

## 快速开始（一个目标）
```bash
# 0) 铺 PATH + 确认引擎在（一次）
export PATH="$(pwd)/bin:$PATH"
# 1) 一键侦察（阶段1+2 自动：子域/官网扫/活体指纹）
bash tools/hunt.sh <domain> [slug] [scope.md]
# 2) 阶段4 开工先建攻击面矩阵（每格终态制：实锤/已试/判死）
bash tools/hunter-cli.sh matrix <slug> <domain>
#    洞型测试由 Agent 按 SOP 严重→低逐型打，判死前强制爬梯子(references/death-escalation-ladder.md)，
#    出实锤写 reports/<slug>/finding_<n>.md，判死写 scratch/<slug>/deadlines.md
# 3) 阶段5 过 FP-elimination+7问；阶段6 用 templates/report-btt-vulbox.md 出报告
```

## 阶段流程
| 阶段 | 内容 | 自动化程度 |
|---|---|---|
| -1 挑分 | 值得打4型/快判死3型/WAF速认表（先筛后打） | 🔧 Agent 判断 |
| 0 范围红线 | 授权范围逐字抄、备案号不脑补、限额记满 | 人工填 scope.md |
| 1 资产测绘 | 子域多渠道（并行DoH+crt.sh+**前端配置挖域**+Wayback+ICP姊妹域）+ 官网源码扫 IP:端口 | ✅ 脚本 |
| 2 活体普查 | 每活资产只看响应头指纹 → 映射洞型（https死自动回退http） | ✅ 脚本 + nuclei |
| 3 面绘制 | 端点 × 前置条件 × 参数矩阵（参数名必抠源码不许猜） | ✅ katana 爬虫 |
| 4 洞型测试 | 严格 严重→低；矩阵每格三终态才准收工；判死前爬梯 L0-L7 | 🔧 Agent + 腿 |
| 5 实锤复核 | FP-elimination → 报前 7 问（可复现/真影响/对照组） | 🔧 Agent |
| 6 报告 | 可复制纯文本 + 截图清单 + 平台适配 | 📋 模板 |

## 硬约束（铁律）
1. **零落地**：只看响应头/状态码/字节数/前几百字节，不下全量 JS/大文件。
2. **实锤**：数据真泄露/真越权/真 RCE/真读文件才算洞；500 报错/返回 success/WAF 拦截页不算。
3. **判死证据制**：判死必须写证据进 journal + 爬完梯子（L0-L7，每级 1-2 发/全梯 ≤15 发）；判死前置=最低三件套(nuclei模板扫+ffuf关键路径+katana爬)或可复核豁免。**"被 WAF 拦"不等于证据穷尽。**
4. **payload 克制**：sleep 1、回显、读 1 行表；不拖全库、不写破坏性 payload。
5. **A8 回显三查**：每个回显参数独立测 注入/XSS canary/跳转 三项，缺一项没资格判死。
6. **对照组**：越权必须 A读B+A读A 双证；race 必须 barrier 同瞬齐射+不变量终态判定。

## 11 条腿（MCP 注册后在 Hermes 里直呼）
| 腿 | 工具 | 阶段 |
|---|---|---|
| 子域+官网扫+活体普查 | `hunter_recon` | 1+2 |
| 单点活体指纹 | `hunter_probe` | 2 |
| 面绘制(端点+JS) | `hunter_crawl` | 3 |
| 非破坏模板扫 | `hunter_scan`（0 命中强制自检提示，防假阴性） | 2/4 |
| 目录/端点 fuzz | `hunter_fuzz`（-or 防旧文件假命中） | 4 |
| 攻击面矩阵骨架 | `hunter_matrix` | 4 开工 |
| 资产快照 diff（新增/鬼资产） | `hunter_monitor` | 持续侦察 |
| 存储XSS 三态 | `hunter_xss`（--then 多步 client-side 流） | 4 |
| 越权双邮箱 | `hunter_accounts` | 越权线 |
| apk 密钥/API 扫描 | `hunter_apk` | A' 移动端 |
| 取脑子 | `hunter_brain(playbook/sop/gates/waf/ladder/race)` | 全程 |

## 工具依赖
- **自研腿**：`tools/hunter-cli.sh`（subs/recon/probe 纯自研，curl + 阿里 DoH + crt.sh）
- **底层引擎**（第三方，藏 `bin/` 不冒头，靠 `tools/install-toolchain.sh` 重建）：`ffuf` / `katana` / `nuclei` / `httpx`（ProjectDiscovery），nuclei 模板本地库在 `bin/templates/`
- **自研专项**：`mailacct.py`（双邮箱）/ `xssprobe.py`（Playwright 三态）/ `apksecret.py`（apk 扫密钥，零 Java）
- 第三方 MCP 无依赖——全流程走自有 tools/ + 引擎
- 本机 IPv6 不稳 → 所有 curl 强制 `-4`；DNS 走阿里 DoH `dns.alidns.com`
- 产物根目录 `HUNTER_SCRATCH` 可配（默认仓库内 `scratch/`，clone 即用）

## 判死速查（写证据后不再磕）
- 未鉴权面全 404/403 + 无弱口令入口 + 无 .git/.bak 可读 → 未鉴权线判死
- 拿不到 2 可用登录态（审核制/滑块/极验）→ 越权/IDOR 线判死
- 自研 WAF 全拦 + 3 种绕过手法均拦 → WAF 线判死（须先爬梯 L1-L6）
- 单 www + 强 WAF + 子域全 404 → 全目标判死（兰大一院型）
- 前端泄露内网 IP 但 DNS 解析进 RFC1918 → 公网不可达，转 L7（SSRF 靶标）再谈

## 换机迁移（两条路，选快的）

### 路线 A：发行版全量包（推荐，无 Go 无代理也行）
仓库 Releases 页下载 **`hunter-full-vX.zip`（~150MB）**——里面已含代码 + 4 引擎 .exe + 11340 nuclei 模板，
解压后一条命令复活（只补 venv/skill/MCP 注册，秒级）：

```
1. 登录 github.com → xux123171-rgb/hunter → Releases → 下载 hunter-full-vX.zip（浏览器下，不用 token）
2. 解压到任意目录（例如 C:\hunter）
3. bash tools/install-hermes.sh        # 引擎/模板已在包里 → 全跳过，只建 venv + 装 skill + 注册 MCP
4. 在 Hermes 里说「打 www.xxxx.com」即可
```

> 前置只要：Git for Windows（git-bash）+ Python/uv（建 venv，Hermes 自带）。**不用装 Go、不用拉模板、不用开代理。**

### 路线 B：git clone 源码路线（要改代码 / 换 Mac / 引擎跟新版）
```bash
git clone <repo-url> hunter && cd hunter
# 前置：Go + uv（见 SETUP.md 第一节）
bash tools/install-toolchain.sh   # 现编 4 引擎 + 拉 11k 模板（带 .hunter-token 时无代理可拉）
bash tools/install-hermes.sh      # 建 venv + 装 skill + 注册 MCP
```

### 发行版维护（两级包，各管各的）
| 包 | 内容 | 什么时候重传 |
|---|---|---|
| `hunter-full-vX.zip`（~150MB，全量） | 代码 + 4 引擎 + 模板 | 引擎大版本更新 / 想让包跟最新代码 |
| `nuclei-templates.tar.gz`（~10MB，仅模板） | 11k 官方模板 | 官方模板更新（几 MB，比全量快 15 倍） |

打全量包：`python -m zipfile -c scratch/hunter-full-vX.zip <各目录>`（排除 .git/.venv/scratch/.hunter-token，脚本见仓库内打包注释）。
上传：Release 的 Upload assets（150MB 走浏览器慢就开代理，命令行见 `tools/push-release.sh` 说明）。

### 日常测试
改完代码先跑离线回归（30 秒、零真实请求、红绿分明）：
```bash
bash tools/test.sh                          # ① MCP 判定(11工具+断言) ② 引擎腿 7 项 ③ 幂等检测
mcp/.venv/Scripts/python.exe mcp/full_test.py --check-live   # 打真实目标（需网络+授权）
```
