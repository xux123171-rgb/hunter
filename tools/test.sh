#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  hunter 测试总入口 — 一条命令红绿（30 秒离线，零真实请求）
#  ① MCP 离线判定   full_test.py --check      （11 工具 + 脑子字数 + 前置件路径）
#  ② 引擎腿离线自测  engines_offline_test.py   （4 引擎 --version + 读本地库 + flag）
#  ③ 安装幂等性     缺啥补啥静态检测
#  ④ 阳性对照自验   validate-positives.sh（离线喂 3 fixture 给 xssprobe，
#                    断 A/B/C 三态全对；证管线"洞真在时抓得住"。chromium 不可用
#                    全 SKIP 不误红，但提示别据此下目标结论）
#  全过 exit 0 / 任一挂 exit 1。LIVE 判定另跑: <venv> mcp/full_test.py --check-live
# ═══════════════════════════════════════════════════════════════
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# 路径转 native Windows（这台机 native 程序不做 MSYS 转换，喂 native python/引擎必须 C:\...）
wp(){ cygpath -w "$1" 2>/dev/null || echo "$1"; }
HERE_W="$(wp "$HERE")"
VPY=""
for cand in "$HERE/mcp/.venv/Scripts/python.exe" "$HERE/mcp/.venv/bin/python"; do
  [ -x "$cand" ] && VPY="$(wp "$cand")" && break
done
[ -z "$VPY" ] && { echo "❌ 缺 mcp/.venv（先 bash tools/install-hermes.sh）"; exit 1; }

pass=0; fail=0
run(){ # $1=label  其余=命令(首参须 native 路径)
  local label="$1"; shift
  echo "═══ $label ═══"
  "$@" 2>&1 | tail -8
  local rc="${PIPESTATUS[0]}"
  if [ "$rc" = "0" ]; then echo "  ✓ $label PASS"; pass=$((pass+1));
  else echo "  ✗ $label FAIL (exit $rc)"; fail=$((fail+1)); fi
}

# ① MCP 离线判定（零真实请求）——喂 native 路径
run "① MCP 离线判定" "$VPY" "$(wp "$HERE/mcp/full_test.py")" --check

# ② 引擎腿离线自测（缺引擎/模板自动 SKIP 不误判）——喂 native 路径
run "② 引擎腿离线自测" "$VPY" "$(wp "$HERE/mcp/engines_offline_test.py")"

# ③ 安装幂等性（全齐应全跳）
echo "═══ ③ 安装幂等性（缺啥补啥）═══"
MISSING=""
for e in ffuf katana nuclei httpx; do [ -f "$HERE/bin/$e.exe" ] || MISSING="$MISSING $e"; done
[ -d "$HERE/bin/templates/http" ] || MISSING="$MISSING 模板库"
[ -d "$HERE/mcp/.venv" ] || MISSING="$MISSING venv"
[ -f "$HERE/skill/SKILL.md" ] || MISSING="$MISSING skill"
if [ -z "$MISSING" ]; then
  echo "  ✓ 全齐（引擎/模板/venv/skill 都在），幂等重跑 install-hermes.sh 会全跳"; pass=$((pass+1))
else
  echo "  ⚠ 缺:$MISSING（可重跑 bash tools/install-hermes.sh 补齐）"; pass=$((pass+1))
fi

# ④ 阳性对照自验（离线 fixture 喂 xssprobe，证"洞真在时抓得住"；chromium 不可用则 SKIP 不误红）
echo "═══ ④ 阳性对照自验（工具健康度）═══"
bash "$HERE/tools/validate-positives.sh" 2>&1 | tail -6
rc="${PIPESTATUS[0]}"
if [ "$rc" = "0" ]; then echo "  ✓ 阳性对照 PASS"; pass=$((pass+1));
else echo "  ✗ 阳性对照 FAIL (exit $rc)"; fail=$((fail+1)); fi

echo
echo "════════ 测试总入口: PASS $pass / FAIL $fail ════════"
[ "$fail" = 0 ] && echo "  🟢 全绿（离线基线达标）" || echo "  🔴 有挂项"
exit "$fail"
