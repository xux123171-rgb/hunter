# SETUP — 环境需求总清单（clone 即用）

> 目标：任何一台 Windows 机器，照这份装齐 → 仓库里**全部 11 条腿**都能跑。
> 已实测基线环境（2026-09，本项目开发/验收机）：Windows 10 + Git Bash + Go 1.27 + uv + Hermes Agent。

## 〇、发行版全量包（最快路线，无 Go 无代理）

仓库 Releases 的 **`hunter-full-vX.zip`（~150MB，含 4 引擎 + 11340 模板 + 全部代码）**，解压后：

```bash
unzip hunter-full-v0.2.zip -d C:\hunter && cd C:\hunter
bash tools/install-hermes.sh    # 引擎/模板已在包里 → 全跳过，只建 venv + 装 skill + 注册 MCP
```

前置仅 Git for Windows（git-bash）+ Python/uv（Hermes 自带则免）。**不装 Go、不拉模板、不开代理。**
模板官方更新了不用下全量包：单独传 v0.1 的 `nuclei-templates.tar.gz`（~10MB）覆盖 `bin/templates/`。

## 一、系统前置（一次性装）

| 组件 | 版本基线 | 装法 | 用途 |
|---|---|---|---|
| Git for Windows | 任意新版 | winget / 官网 | 提供 git-bash（**自研腿 subs/probe/recon 全靠它**）+ git |
| Go | ≥1.17（实测 1.27） | winget install GoLang.Go | 编译 4 引擎（脚本走 `goproxy.cn`，国内不挂） |
| uv | 任意新版 | winget / `pipx` / Hermes 自带 | 建 `mcp/.venv`（FastMCP 服务） |
| curl / unzip | git-bash 自带 | 无需单独装 | DoH 子域枚举 / nuclei 模板 zip |
| Python | 3.10+（可选，仅 xss 腿） | 见下方第 4 项 | 跑 `xssprobe.py` / `mailacct.py` 子进程 |

> Linux/macOS 同样可行：把下表的 Windows 路径换成系统对应物（`bash`、`~/.local/share/.../venv/bin/python` 等），
> `install-toolchain.sh` 的 `go install` 段跨平台（产物不带 .exe，改 `bin/` 下文件名或在 `MANIFEST.md` 标注）。

## 二、clone 后一条命令：

```bash
git clone <repo-url> hunter && cd hunter
bash tools/install-toolchain.sh
```

它自动做 4 件事（缺前置会报错提示，不会瞎装）：
1. **4 引擎** → `bin/`：katana / nuclei / ffuf / httpx（ProjectDiscovery 系，第三方，藏 bin/ 不冒头）
2. **nuclei 模板本地化** → `bin/templates/`（~11k 官方 zip，国内自动走 `ghproxy.net` 加速兜底）
3. **MCP venv** → `mcp/.venv`（`mcp[cli]<2` 的 FastMCP）
4. **Playwright 检查**（xss 腿专用）：找 Python 宿主（`HUNTER_PYTHON` > Hermes agent venv > 系统 python），
   缺 playwright 就自动 `pip install playwright && playwright install chromium`

## 三、MCP 注册（Hermes，可选但推荐）

纯 CLI（`bash tools/hunt.sh <domain>`）不装 MCP 也能全流程。要 11 工具 MCP 形态：

```
# Hermes config.yaml
mcp_servers:
  hunter:
    command: "<repo>/mcp/.venv/Scripts/python.exe"
    args: ["<repo>/mcp/server.py"]
```

或 CLI 一把注册：

```bash
hermes mcp add hunter \
  --command "<repo>/mcp/.venv/Scripts/python.exe" \
  --args "<repo>/mcp/server.py" <<< "Y"
```

启动新会话即加载 11 工具：`hunter_recon / probe / crawl / scan / fuzz / matrix / monitor / xss / accounts / apk / brain`。

## 四、环境变量（全有默认值，不设也能跑；要跨机/跨用户再设）

| 变量 | 默认 | 说明 |
|---|---|---|
| `HUNTER_HOME` | 不设也能跑（`server.py` 从 `__file__` 自动定位到 clone 的仓库根；仅多副本/分离安装时需显式设） | 指向仓库根 |
| `HUNTER_PYTHON` | 自动发现（Hermes agent venv → PATH python） | 跑 xssprobe/mailacct/apksecret 子进程的解释器，需含 playwright |
| `HUNTER_SLUG` | 由 URL 自动推 | 指定 scratch 工作目录名 |
| `HUNTER_SCRATCH` | 仓库内 `scratch/`（clone 即用） | 侦察/fuzz/crawl 产物根目录；本机想指回 `D:/research/scratch` 在此设 |

> 快速改 `HUNTER_HOME`：`bash -c 'export HUNTER_HOME=<你的clone路径>; ...'`
> 或 Windows 系统环境变量加一条。

## 五、验证全通（1 条命令，防回归）

```bash
cd mcp && .venv/Scripts/python.exe full_test.py          # 11 工具全打一遍（需一个已探过活的域名）
```

分 3 批避免前台超时（nuclei 慢）：

```bash
.venv/Scripts/python.exe full_test.py brain accounts probe crawl fuzz xss
.venv/Scripts/python.exe full_test.py recon
.venv/Scripts/python.exe full_test.py scan
```

预期：11/11 返回内容非空、无 `timed out` / `Connection closed`。

## 六、常见坑（本项目实测踩过，写死给你）

| 现象 | 原因 | 解法 |
|---|---|---|
| MCP 里 probe/crawl 90s 超时 | 子进程继承了 MCP stdio 协议管道 | 已在 `server.py` 修（`stdin=DEVNULL`），**别删那行** |
| nuclei 显示 0 命中但没跑 | 没传本地模板目录 / 默认找家目录 | `cmd_scan` 已带 `-t bin/templates/http`；手动跑也记得 `-t` |
| katana 写不出端点文件 | MSYS `/c/...` 路径喂原生 Go 程序 | `hunter-cli.sh` 已加 `wp()`（cygpath 转换），**别把 WP 改回绝对 MSYS 路径** |
| ffuf 打 usage | `-retries` 是 1.x 参数，2.x 没有 | 已删，用 `-t`（threads） |
| 中文乱码（Windows 原生 python 子进程） | stdout 默认 GBK | `server.py` 已钉 `PYTHONIOENCODING=utf-8` |
| 杀毒软件弹"检测到威胁" | nuclei/ffuf/katana/httpx 启发式误报（隔离区不会删） | `tools/add-defender-exclusion.ps1`（需管理员 PowerShell） |
| GitHub 直连断流（国内机） | 网络间歇 reset | 代理；或让 `install-toolchain.sh` 走 `ghproxy.net`（已内置兜底） |
| MCP 服务注册了但工具没出现 | config.yaml 改完没重开会话 | 开新会话（MCP 工具表是会话启动快照） |

## 七、目录资产盘点（哪些在 git，哪些靠脚本重建）

```
在 git（clone 即有）:
  sop/ PLAYBOOK.md + SOP.md            ← 脑子
  references/ 3 篇方法论               ← 脑子扩展（WAF绕过/race/封顶表）
  tools/ 6 自研 + wordlists + install-toolchain + push-to-github
  mcp/ server.py + full_test.py        ← MCP 服务本体
  templates/ 报告骨架
  README.md / SETUP.md / .gitignore

不在 git（体积/gitignore，install-toolchain.sh 一条命令重建）:
  bin/*.exe            ← go install 4 引擎
  bin/templates/       ← nuclei 官方 zip（ghproxy 兜底）
  mcp/.venv            ← uv venv + mcp[cli]<2
  scratch/ journal/ reports/  ← 工作产物，用完即删（SOP 纪律）
```
