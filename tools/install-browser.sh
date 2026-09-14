# install-browser.sh — xssprobe 依赖的两个浏览器环境（可被 install-toolchain.sh / install-hermes.sh source 或直接跑）
# 提取自 install-toolchain.sh，使"一键装进 Hermes"也能补齐浏览器二进制（此前 ⑥ 只在 toolchain 里，一键路径永不触发）。
# 幂等：已有就跳，缺才装。需要 uv / python 宿主；都缺则报不可用但 return 0（不挡其他腿）。

# xssprobe 依赖 Playwright（浏览器端存储XSS 腿）
# Python 宿主解析：HUNTER_PYTHON 显式 > Hermes agent venv（含 playwright）> 系统 python
# 跨机可移植，不写死某台机器路径
setup_playwright() {
  local PY
  if [ -n "${HUNTER_PYTHON:-}" ]; then PY="$HUNTER_PYTHON"
  elif [ -n "${LOCALAPPDATA:-}" ] && [ -f "${LOCALAPPDATA}/hermes/hermes-agent/venv/Scripts/python.exe" ]; then PY="${LOCALAPPDATA}/hermes/hermes-agent/venv/Scripts/python.exe"
  else PY="$(command -v python || echo "")"; fi
  [ -z "$PY" ] && { echo "==> 未找到 Python 宿主，跳过（xssprobe 腿不可用，不影响其他腿；设 HUNTER_PYTHON 可指一个装了 playwright 的解释器）"; return 0; }
  if "$PY" -c "import playwright" >/dev/null 2>&1; then
    echo "==> playwright 已在（$PY），xssprobe 可用"
  else
    echo "==> 装 playwright + chromium 进 $PY（xssprobe 需要）"
    "$PY" -m pip install -q playwright 2>&1 | tail -1
    "$PY" -m playwright install chromium 2>&1 | tail -1
  fi
}

# ⑥ 浏览器二进制兜底：agent-browser 的 chrome-for-testing 内置 install 直连 Google（国内断流）
# 检测缺失 → 从 npmmirror 官方镜像拉 CFT zip → 平铺（zip 内套 chrome-win64/ 要提一层）
setup_browser() {
  local CFT="${HOME}/.agent-browser/browsers/chrome-for-testing/153.0.8010.36/win64/chrome.exe"
  if [ -f "$CFT" ]; then
    echo "==> 浏览器二进制已在（$CFT），xssprobe/agent-browser 可用"; return 0
  fi
  echo "==> chrome-for-testing 缺失，拉官方镜像（npmmirror，国内可达）…"
  local tmp; tmp="$(mktemp -d)"
  # zip 内层是 chrome-win64/，要把内层平铺到 win64/（agent-browser 期望 .../win64/chrome.exe）
  if curl -sk4 -m 300 -o "$tmp/cft.zip" "https://cdn.npmmirror.com/binaries/chrome-for-testing/153.0.8010.36/win64/chrome-win64.zip" 2>/dev/null \
     && [ "$(wc -c < "$tmp/cft.zip" 2>/dev/null | tr -d ' ')" -gt 50000000 ]; then
    mkdir -p "$(dirname "$CFT")"
    unzip -q "$tmp/cft.zip" -d "$tmp/" 2>/dev/null
    # 内层 chrome-win64/ 提一层到 win64/
    if [ -d "$tmp/chrome-win64" ]; then cp -r "$tmp/chrome-win64/." "$(dirname "$CFT")/"; fi
    [ -f "$CFT" ] && echo "  ✓ 浏览器二进制 -> $CFT" || echo "  ⚠ 平铺失败，手动解压 $tmp/cft.zip"
    rm -rf "$tmp"
  else
    echo "  ⚠ 浏览器二进制拉取失败（断流）——xssprobe 腿暂不可用，不影响其他腿；稍后重跑本脚本补齐"
  fi
}

# 直接跑（非 source）时执行一遍
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  setup_playwright
  setup_browser
fi
