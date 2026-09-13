# 工具链清单（hunter/bin）

五个二进制 = 我们的"腿"。脑子是 `sop/SOP.md`，接线在 `tools/EXEC.md` 第二节。

| 工具 | 版本 | 大小 | 干什么 | 挂哪个阶段 |
|---|---|---|---|---|
| `subfinder`(可选) | - | - | 子域被动枚举；**本机没装，走 cybermes 的 crt.sh 引擎兜底** | 阶段1 |
| `katana.exe` | v1.7.0 | 61M | SPA/端点/JS 爬虫，挖隐藏路由 | 阶段3 |
| `nuclei.exe` | v3.11.1 | 171M | 非破坏模板扫（exposed-panels/misconfig/cve/auth-bypass） | 阶段2/4 |
| `ffuf.exe` | - | 16M | 目录/参数/隐藏路径 fuzz（限速） | 阶段4 |
| `httpx.exe` | v1.12.0 (PD) | 66M | 活体指纹（tech stack/标题/状态码） | 阶段2 |
| `cybermes-mcp.exe` | - | 16M | MCP 工具腿：子域/http_probe/fuzz/crawl/secret 扫/报告聚合（可选加速器，不用也能全流程） | 全程 |
| `templates/`（nuclei 模板库） | ~11k http 模板 | 本地 | 本地化根治国内拉取不稳；`bin/templates/` 只留本地不入 git，`tools/install-toolchain.sh` 的 `download_templates` 拉取 | 阶段2/4 |

> `httpx` 必须是 **ProjectDiscovery httpx**（指纹器），不是 Python 的 `httpx` 包（那是 HTTP 客户端库，完全两码事）。装错了阶段2 就废。

## 可复现重装（本机 GitHub 断流 → 走 goproxy.cn）
```bash
export GOPROXY=https://goproxy.cn,direct
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/ffuf/ffuf/v2@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
# subfinder 二进制 GitHub release 国内下不动，跳过（cybermes crt.sh 兜底）
# cybermes-mcp：来自 Zyrexnn/Cybermes，MCP 服务器，见 tools/EXEC.md
```

## 一条命令铺进 PATH（让 shell 直接能用）
```bash
export HUNTER_BIN="/c/Users/ThinkPad/Documents/src-xiaoxu/hunter/bin"
export PATH="$HUNTER_BIN:$PATH"
```
铺好后 `katana -version` / `nuclei -version` / `ffuf -v` / `httpx -version` 直接可用。
