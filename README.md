# hunter — 合规 Web 漏洞挖掘流水线

一套**全谱系、严重→低危、零落地**的 Web 漏洞挖掘方法论 + 自动化工具链。
核心思想：**脑子是 SOP（打哪类洞、什么顺序、实锤/判死标准），腿是自研工具（hunter-cli 编排 + ffuf/katana/nuclei/httpx 底层引擎 + 自研 python 工具）**。
不靠"经验型"预设打法——每个目标从头走完 6 个阶段，出洞按实锤判定，判死按证据判定。

> 仅用于**授权范围内**的安全测试（SRC/补天/漏洞盒子等）。默认合规：注入只证可读、payload 克制（sleep 1/回显/读 1 行）、越权读限额、禁扫描器/社工/内网渗透/DDoS。

## 目录
```
hunter/
├── sop/SOP.md                # 脑子：6 阶段作战流程（阶段0范围→6报告）+ 阶段门 + 判死条件
├── references/               # 方法论扩展
│   ├── impact-priority-gates.md   # 影响框架/合规硬限/FP排除/阶段门/合规深度封顶表
│   ├── waf-bypass.md              # 强防护合规绕过（源站直连/混淆/逻辑面）
│   └── race-business-logic.md     # 业务逻辑 + 并发 race（WAF 盲区）
├── tools/
│   ├── EXEC.md           # 腿：自有工具链、截图配方、补天字段、清理、判死速查
│   ├── hunter-cli.sh     # 自有统一入口：subs/probe 纯自研 + crawl/scan/fuzz 调引擎
│   ├── mailacct.py       # 合规双邮箱账号（越权双号，mail.tm 收件侧）
│   ├── xssprobe.py       # 存储XSS 三态判定（Playwright 元素级 canary）
│   ├── hunt.sh           # 一键跑 阶段0-3（自动部分），把面摊开给 Agent
│   ├── hunt-recon.sh     # 阶段1+2：子域枚举 + 官网扫 + 活体指纹普查
│   ├── install-toolchain.sh  # 可复现重建 4 引擎 + nuclei 模板本地库
│   └── push-to-github.sh # 推私有仓库（P 方式，token 走本地文件）
├── bin/                    # 底层引擎（第三方，gitignore 挡出 git，靠 install 重建）
│   ├── ffuf.exe katana.exe nuclei.exe httpx.exe
│   ├── templates/         # nuclei 模板本地库（~11k http，只留本地）
│   └── MANIFEST.md + VENDOR.md
├── templates/
│   ├── finding-poc.md       # finding + PoC 骨架
│   └── report-btt-vulbox.md # 补天/盒子可复制报告模板
├── mcp/                     # 我们自己的 MCP 服务（FastMCP stdio，8工具全自研）
│   ├── server.py            # recon/probe/crawl/scan/fuzz/xss/accounts/brain
│   └── full_test.py         # 8工具一键复测（防回归）
├── journal/<目标>/       # 出洞归档：scope/report/finding/截图清单
├── scratch/<目标>/       # 工作产物（assets/probe/endpoints），打完即删
└── reports/<目标>/       # 报告 + 证据
```

## 快速开始（一个目标）
```bash
# 0) 铺 PATH + 确认引擎在（一次）
export PATH="$(pwd)/bin:$PATH"
# 1) 一键侦察（阶段0-3，自动）
bash tools/hunt.sh <domain> [slug] [scope.md]
# 2) 阶段4 洞型测试（严重→低）由 Agent 按 SOP 4.1→4.4 逐型打，
#    出实锤写 reports/<slug>/finding_<n>.md，判死写 scratch/<slug>/deadlines.md
# 3) 阶段5 过 7 问；阶段6 用 templates/report-btt-vulbox.md 出报告
```

## 六阶段
| 阶段 | 内容 | 自动化程度 |
|---|---|---|
| 0 范围红线 | 授权范围逐字抄、备案号不脑补、限额记满 | 人工填 scope.md |
| 1 资产测绘 | 子域枚举（DoH 批量 + crt.sh）+ 官网源码扫 IP:端口 | ✅ 脚本 |
| 2 活体普查 | 每活资产只看响应头指纹 → 映射洞型 | ✅ 脚本 + nuclei |
| 3 面绘制 | 端点 × 前置条件 × 参数矩阵 | ✅ katana 爬虫 |
| 4 洞型测试 | 严格 严重→低，出实锤即停该型 | 🔧 Agent 判断 |
| 5 实锤复核 | 报前 7 问（可复现/真影响/对照组） | 🔧 Agent |
| 6 报告 | 可复制纯文本 + 截图清单 + 平台适配 | 📋 模板 |

## 硬约束（铁律）
1. **零落地**：只看响应头/状态码/字节数/前几百字节，不下全量 JS/大文件。
2. **实锤**：数据真泄露/真越权/真 RCE/真读文件才算洞；500 报错/返回 success/WAF 拦截页不算。
3. **判死证据制**：判死必须写证据进 journal，不靠"经验"（lzdxdyyy 型 = 单 www+强 WAF+子域全 404）。
4. **payload 克制**：sleep 1、回显、读 1 行表；不拖全库、不写破坏性 payload。

## 工具依赖
- **自研腿**：`tools/hunter-cli.sh`（subs/probe 纯自研，curl + 阿里 DoH + crt.sh）
- **底层引擎**（第三方，藏 `bin/` 不冒头，靠 `tools/install-toolchain.sh` 重建）：`ffuf` / `katana` / `nuclei` / `httpx`（ProjectDiscovery），nuclei 模板本地库在 `bin/templates/`
- **自研专项工具**：`tools/mailacct.py`（合规双邮箱账号）/ `tools/xssprobe.py`（存储XSS 三态判定）
- 第三方 MCP（cybermes）已移除——全流程走自有 tools/ + 引擎，无外部 MCP 依赖
- 本机 IPv6 不稳 → 所有 curl 强制 `-4`；DNS 走阿里 DoH `dns.alidns.com`

## 判死速查（不再磕）
- 未鉴权面全 404/403 + 无弱口令入口 + 无 .git/.bak 可读 → 未鉴权线判死
- 拿不到 2 可用登录态（审核制/滑块/极验）→ 越权/IDOR 线判死
- 自研 WAF 全拦 + 3 种绕过手法均拦 → WAF 线判死
- 单 www + 强 WAF + 子域全 404 → 全目标判死

## 换机迁移（clone 即用）
仓库自带全部**脑子**（sop/ + references/ + PLAYBOOK.md）+ 全部**自研腿**（tools/ + mcp/server.py），
换机 3 步（完整环境清单/变量/踩坑表见 **`SETUP.md`**）：

```bash
git clone <repo> hunter && cd hunter
# 前置：装 Go + uv（引擎编译 / MCP venv，见 SETUP.md 第一节）
bash tools/install-toolchain.sh   # 一条命令重建 bin/ 4引擎 + 11k nuclei模板 + mcp/.venv + playwright
# Hermes 里注册 MCP（可选，不装也能纯 CLI 全流程）：
#   mcp_servers.hunter.command = <repo>/mcp/.venv/Scripts/python.exe
#   mcp_servers.hunter.args    = [<repo>/mcp/server.py]
# 别的机器改 HUNTER_HOME 指向你的 clone 路径（自动发现逻辑在 mcp/server.py，无需改代码）
```

不在 git 里（体积大，靠脚本重建）：`bin/*.exe`（go install）、`bin/templates/`（官方 zip + ghproxy 兜底）、
`mcp/.venv`（uv + mcp[cli]<2）。国内机 GitHub 直连断流时走 `ghproxy.net` 前缀，脚本已内置。
