#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  hunter 一键装进 Hermes — 跟第三方 MCP 一样，一条命令搞定
#
#  做什么（全是"缺了才装，有了就跳"，可反复跑）：
#    ① 引擎   bin/{ffuf,katana,nuclei,httpx}.exe   （go install，可跳）
#    ② 模板   bin/templates/                        （nuclei 本地库）
#    ③ venv   mcp/.venv                             （MCP 服务 Python）
#    ④ skill  <Hermes skills>/hunter                （脑子，按需加载）
#    ⑤ MCP    hermes mcp add hunter                 （腿，注册进 Hermes）
#
#  用法：  bash tools/install-hermes.sh
#  依赖：  git for Windows + Go + uv（系统级，已有则零操作）
# ═══════════════════════════════════════════════════════════════
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
say(){ echo "══ $1 ══"; }
skip(){ echo "   ✓ 已有，跳过：$1"; }

# ── 系统级依赖（不装，只报）────────────────────────────
command -v git >/dev/null || { echo "❌ 缺 git（Git for Windows）"; exit 1; }
GO=""; command -v go >/dev/null 2>&1 && GO=$(command -v go)
UV=""; command -v uv >/dev/null 2>&1 && UV=$(command -v uv)
[ -n "$GO" ] && say "Go: $GO"        || echo "   ⚠ 无 go → 引擎步跳过（你已有就无所谓）"
[ -n "$UV" ] && say "uv: $UV"        || echo "   ⚠ 无 uv → venv 步用系统 python 兜底"

# ── ① 引擎（我有的不装，缺哪个补哪个）─────────────────────
say "① 引擎 bin/"
mkdir -p "$HERE/bin"
for e in ffuf katana nuclei httpx; do
  if [ -f "$HERE/bin/$e.exe" ]; then skip "bin/$e.exe"; continue; fi
  [ -n "$GO" ] || { echo "   ⚠ bin/$e.exe 缺且无 go，跳过"; continue; }
  echo "   补 bin/$e.exe …"
  case $e in
    ffuf)    go install github.com/ffuf/ffuf/v2@latest 2>&1 | tail -1 ;;
    katana)  go install github.com/projectdiscovery/katana/cmd/katana@latest 2>&1 | tail -1 ;;
    nuclei)  go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest 2>&1 | tail -1 ;;
    httpx)   go install github.com/projectdiscovery/httpx/cmd/httpx@latest 2>&1 | tail -1 ;;
  esac
  cp -f "$(go env GOPATH)/bin/$e.exe" "$HERE/bin/$e.exe" 2>/dev/null && echo "   ✓ $e" || echo "   ⚠ $e 装失败"
done

# ── ② nuclei 模板 → 挪到最后（慢且不挡核心），见脚本尾部 ──────
# ── ③ MCP venv（MCP 服务跑起来的 Python）──────────────────
say "③ MCP venv mcp/.venv"
if [ -f "$HERE/mcp/.venv/Scripts/python.exe" ] || [ -x "$HERE/mcp/.venv/bin/python" ]; then
  skip "mcp/.venv"
else
  if [ -n "$UV" ]; then
    ( cd "$HERE/mcp" && uv venv .venv 2>&1 | tail -1 && uv pip install -q 'mcp[cli]<2' 2>&1 | tail -1 )
  else
    ( cd "$HERE/mcp" && python -m venv .venv 2>&1 | tail -1 && .venv/Scripts/python -m pip install -q 'mcp[cli]<2' 2>&1 | tail -1 )
  fi
  echo "   ✓ mcp/.venv"
fi

# ── ④ skill（脑子，放 Hermes skills 目录；按需加载）────────
say "④ skill → Hermes skills/"
SKILL_ROOT=""
for cand in "$LOCALAPPDATA/hermes/skills" "$HOME/.hermes/skills" "$HOME/AppData/Local/hermes/skills"; do
  [ -d "$cand" ] && SKILL_ROOT="$cand" && break
done
if [ -z "$SKILL_ROOT" ]; then echo "   ⚠ 找不到 Hermes skills 目录（Hermes 没装？）"; else
  DEST="$SKILL_ROOT/hunter"
  # skill 本体 = 仓库里 skill/ 目录（脑子：SOP/Playbook/铁律）
  if [ -d "$HERE/skill" ]; then
    rm -rf "$DEST"; cp -r "$HERE/skill" "$DEST"; echo "   ✓ skill → $DEST"
  else
    echo "   ⚠ 仓库无 skill/ 目录，脑子靠 MCP 的 hunter_brain（MCP 自包含，可无 skill）"
  fi
fi

# ── ⑤ 注册 MCP 进 Hermes（腿；幂等，已有就更新路径）────────
say "⑤ hermes mcp add hunter"
command -v hermes >/dev/null 2>&1 || { echo "   ⚠ 无 hermes 命令，手动注册：hermes mcp add hunter --command <venv-python> --args $HERE/mcp/server.py"; }
if command -v hermes >/dev/null 2>&1; then
  PYPATH=""
  for cand in "$HERE/mcp/.venv/Scripts/python.exe" "$HERE/mcp/.venv/bin/python"; do
    [ -e "$cand" ] && PYPATH="$cand" && break
  done
  # 转成 native Windows 路径喂 hermes（MSYS 里要 cypath）
  NATIVE=$(cygpath -w "$PYPATH" 2>/dev/null || echo "$PYPATH")
  SRVPATH=$(cygpath -w "$HERE/mcp/server.py" 2>/dev/null || echo "$HERE/mcp/server.py")
  hermes mcp add hunter --command "$NATIVE" --args "$SRVPATH" <<< "Y" >/dev/null 2>&1
  hermes mcp list 2>&1 | grep -i hunter | head -2
fi

# ── ② nuclei 模板（放最后：慢、且只增强 scan 一条腿，不挡其余 7 腿）─
say "② nuclei 模板 bin/templates/（最后，可后台）"
if [ -d "$HERE/bin/templates/http" ] && [ "$(find "$HERE/bin/templates/http" -name '*.yaml' 2>/dev/null | wc -l)" -gt 100 ]; then
  skip "bin/templates（$(find "$HERE/bin/templates/http" -name '*.yaml' | wc -l) 模板）"
else
  echo "   拉模板（断点续传）…失败不挡，稍后重跑本脚本即可补齐"
  bash "$HERE/tools/download-templates.sh" 2>&1 | tail -3
fi

echo
say "完。现在在 Hermes 里说「打 www.xxxx.com」即可（脑子 skill / 腿 MCP 都在）。"
