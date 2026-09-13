#!/usr/bin/env bash
# hunter install-toolchain.sh — 可复现重装 5 个二进制进 hunter/bin/
# 本机 GitHub 直连断流 → 走 goproxy.cn。缺 go 就报错退出。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$HERE/bin"; mkdir -p "$BIN"
echo "目标 bin: $BIN"

command -v go >/dev/null 2>&1 || { echo "缺 go，先装 Go 再跑本脚本"; exit 1; }
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

echo "==> katana";   go install github.com/projectdiscovery/katana/cmd/katana@latest    2>&1 | tail -1
echo "==> nuclei";   go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest 2>&1 | tail -1
echo "==> ffuf";     go install github.com/ffuf/ffuf/v2@latest                          2>&1 | tail -1
echo "==> httpx(PD)";go install github.com/projectdiscovery/httpx/cmd/httpx@latest      2>&1 | tail -1

# go 装完在 ~/go/bin，拷进项目 bin/（httpx 必须是 PD 版，别被 Python shim 覆盖）
GBIN="$(go env GOPATH)/bin"
for t in katana.exe nuclei.exe ffuf.exe httpx.exe; do
  [ -f "$GBIN/$t" ] && cp -f "$GBIN/$t" "$BIN/$t" && echo "  拷 $t" || echo "  缺 $GBIN/$t"
done

# 我们的 hunter-mcp（可选加速器）：脑子(SOP)留 skill，腿做成 MCP 类型化工具，全指向本项目
# 起法（Hermes config.yaml）：
#   mcp_servers:
#     hunter:
#       command: "C:\\Users\\ThinkPad\\AppData\\Local\\hermes\\hermes-agent\\venv\\Scripts\\python.exe"
#       args: ["C:\\Users\\ThinkPad\\Documents\\src-xiaoxu\\hunter\\mcp\\server.py"]
# venv 重建：cd mcp && uv venv .venv && uv pip install -q 'mcp[cli]<2'
echo "  hunter-mcp（可选）: $HERE/mcp/server.py，注册见上方注释；无它也能纯 tools/ 全流程"

echo; echo "=== 核对 bin/ ==="
ls -la "$BIN" | grep -E '\.exe|MANIFEST'
echo "PATH 铺开: export PATH=\"$BIN:\$PATH\"（见 bin/MANIFEST.md）"

# ------------------------------------------------------------------
# nuclei 模板本地化：根治国内直连拉取不稳
# 官方 release zip 一次下到 bin/templates/（gitignore 挡出 git，数据资产只留本地）
# ------------------------------------------------------------------
download_templates() {
  local dst="$BIN/templates"
  if [ -d "$dst/http" ] && [ "$(find "$dst/http" -name '*.yaml' | wc -l)" -gt 100 ]; then
    echo "==> nuclei 模板已就位（$(find "$dst/http" -name '*.yaml' | wc -l) 个 http 模板），跳过"
    return 0
  fi
  mkdir -p "$HERE/scratch"; rm -rf "$dst" scratch/nuclei-templates.zip
  echo "==> 拉 nuclei-templates（官方 main zip，国内可加加速前缀）"
  local url="https://github.com/projectdiscovery/nuclei-templates/archive/refs/heads/main.zip"
  # 国内 GitHub 直连常断 → 自动试 ghproxy 加速镜像
  for u in "https://ghproxy.net/$url" "$url"; do
    if curl -sk4L -m 400 -o scratch/nuclei-templates.zip "$u" 2>/dev/null \
       && [ "$(wc -c < scratch/nuclei-templates.zip | tr -d ' ')" -gt 1000000 ]; then
      echo "  下载自: $u"
      break
    fi
  done
  if [ ! -s scratch/nuclei-templates.zip ]; then
    echo "  模板下载失败（网络受限）——nuclei 仍可跑内置/少量模板，但不影响主流程（人工测为主）"; return 1
  fi
  unzip -q scratch/nuclei-templates.zip -d "$BIN/" 2>/dev/null && \
    mv "$BIN/nuclei-templates-main" "$dst" 2>/dev/null
  echo "  http 模板数: $(find "$dst/http" -name '*.yaml' 2>/dev/null | wc -l)"
  # 让 nuclei 认本地库：用 -t 指本地子目录（-tl 列出该目录全部）
  echo "  用法: bin/nuclei.exe -u <url> -t \"$dst/http/misconfiguration\" -severity critical,high"
  echo "  或全量: bin/nuclei.exe -u <url> -t \"$dst/http\" -rl 10（国内已本地化，不再联网拉模板）"
}
download_templates
# ------------------------------------------------------------------
# hunter MCP 服务 venv（mcp/server.py 跑起来的 Python 环境）
# ------------------------------------------------------------------
setup_mcp() {
  local mcpdir="$HERE/mcp"
  mkdir -p "$mcpdir"
  if [ -f "$mcpdir/.venv/Scripts/python.exe" ] || [ -x "$mcpdir/.venv/bin/python" ]; then
    echo "==> hunter-mcp venv 已存在，跳过（mcp/.venv）"
    return 0
  fi
  echo "==> 建 hunter-mcp venv（需 uv；mcp<2 的 FastMCP）"
  command -v uv >/dev/null 2>&1 || { echo "  缺 uv，先 install uv 再跑"; return 1; }
  ( cd "$mcpdir" && uv venv .venv 2>&1 | tail -2 \
      && uv pip install --python "$(uv python find .venv 2>/dev/null || echo .venv)" -q 'mcp[cli]<2' 2>&1 | tail -2 )
  echo "  起服务: <repo>/mcp/.venv/Scripts/python.exe mcp/server.py（见 mcp/server.py 头部注册说明）"
}
setup_mcp
# ------------------------------------------------------------------
# xssprobe 依赖 Playwright（浏览器端存储XSS 腿）
# Python 宿主解析：HUNTER_PYTHON 显式 > Hermes agent venv（含 playwright）> 系统 python
# 跨机可移植，不再写死某台机器路径
# ------------------------------------------------------------------
setup_playwright() {
  local PY
  if [ -n "${HUNTER_PYTHON:-}" ]; then PY="$HUNTER_PYTHON"
  elif [ -n "${LOCALAPPDATA:-}" ] && [ -f "${LOCALAPPDATA}/hermes/hermes-agent/venv/Scripts/python.exe" ]; then PY="${LOCALAPPDATA}/hermes/hermes-agent/venv/Scripts/python.exe"
  else PY="$(command -v python || echo "")"; fi
  [ -z "$PY" ] && { echo "==> 未找到 Python 宿主，跳过（xssprobe 腿不可用，不影响其他 7 腿；设 HUNTER_PYTHON 可指一个装了 playwright 的解释器）"; return 0; }
  if "$PY" -c "import playwright" >/dev/null 2>&1; then
    echo "==> playwright 已在（$PY），xssprobe 可用"
  else
    echo "==> 装 playwright + chromium 进 $PY（xssprobe 需要）"
    "$PY" -m pip install -q playwright 2>&1 | tail -1
    "$PY" -m playwright install chromium 2>&1 | tail -1
  fi
}
setup_playwright
