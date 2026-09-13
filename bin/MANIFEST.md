# 工具链清单（hunter/bin）

四个底层引擎 = 我们的"腿"。脑子是 `sop/SOP.md`，自研腿在 `tools/`，接线在 `tools/EXEC.md`。

| 工具 | 版本 | 大小 | 干什么 | 挂哪个阶段 |
|---|---|---|---|---|
| `katana.exe` | v1.7.0 | 61M | SPA/端点/JS 爬虫，挖隐藏路由 | 阶段3 |
| `nuclei.exe` | v3.11.1 | 171M | 非破坏模板扫（exposed-panels/misconfig/cve/auth-bypass） | 阶段2/4 |
| `ffuf.exe` | v2.1 | 16M | 目录/参数/隐藏路径 fuzz（限速） | 阶段4 |
| `httpx.exe` | v1.12.0 (PD) | 66M | 活体指纹（tech stack/标题/状态码） | 阶段2 |
| `templates/`（nuclei 模板库） | ~11k http 模板 | 本地 | 本地化根治国内拉取不稳；`bin/templates/` 只留本地不入 git，`tools/install-toolchain.sh` 的 `download_templates` 拉取 | 阶段2/4 |

> **定位**：这四个是**第三方底层引擎**，藏 `bin/` 里被自有 `tools/hunter-cli.sh` 调用，不对外冒头；
> 子域/活体/专项（双邮箱/XSS）全走**自研** `tools/`，无外部 MCP 依赖。
> `httpx` 必须是 **ProjectDiscovery httpx**（指纹器），不是 Python 的 `httpx` 包（那是 HTTP 客户端库，完全两码事）。装错了阶段2 就废。

## 可复现重装（本机 GitHub 断流 → 走 goproxy.cn）
```bash
export GOPROXY=https://goproxy.cn,direct
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/ffuf/ffuf/v2@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
# 子域走 hunter-cli subs 的 阿里 DoH + crt.sh 自研引擎（subfinder 国内 release 下不动，不需要）
# nuclei 模板库：bash tools/install-toolchain.sh 自动 download_templates（zip + ghproxy 加速）
```

## 一条命令铺进 PATH（让 shell 直接能用；路径按你的 clone 位置改）
```bash
export HUNTER_BIN="$(cd "$(dirname "$0")/../bin" && pwd)"   # 或手填：.../hunter/bin
export PATH="$HUNTER_BIN:$PATH"
```
铺好后 `katana -version` / `nuclei -version` / `ffuf -v` / `httpx -version` 直接可用。
