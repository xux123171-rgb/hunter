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

# cybermes-mcp：MCP 服务器，本机在 $HOME/AppData/Local/hermes/bin/cybermes-mcp.exe
CM_SRC="$HOME/AppData/Local/hermes/bin/cybermes-mcp.exe"
if [ -f "$CM_SRC" ]; then
  cp -f "$CM_SRC" "$BIN/cybermes-mcp.exe" && echo "  拷 cybermes-mcp"
else
  echo "  未找到 $CM_SRC；cybermes-mcp 可选（有它走 MCP 工具腿，没它走 Go 二进制 fallback）"
fi

echo; echo "=== 核对 bin/ ==="
ls -la "$BIN" | grep -E '\.exe|MANIFEST'
echo "PATH 铺开: export PATH=\"$BIN:\$PATH\"（见 bin/MANIFEST.md）"
