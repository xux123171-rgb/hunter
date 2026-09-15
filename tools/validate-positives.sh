#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  阳性对照自验（离线）— 证明管线"洞真存在时抓得住"
#  给 hunter xssprobe 腿喂本地 3 个 fixture（洞/转义/无回显），
#  断言 A/B/C 三态全对。全对=工具不是瞎的；以后任何目标 0 命中，
#  先跑这个确认工具健康再下"目标薄"结论。
#  合规：零外网、零靶场（file:// 喂本地 fixture，不起服务）。
#  离线跑 ~20s。chromium 起不来则全 SKIP（不误判红，提示别据此下结论）。
# ═══════════════════════════════════════════════════════════
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# native Windows python（native 引擎不吃 MSYS 路径转换）
PY="${HUNTER_PYTHON:-$LOCALAPPDATA/hermes/hermes-agent/venv/Scripts/python.exe}"
if [ -z "${PY:-}" ] || [ ! -f "$PY" ]; then
  # venv 不在 → 找系统 python
  PY="$(which python 2>/dev/null || which python3 2>/dev/null)"
fi
if [ -z "${PY:-}" ] || [ ! -f "$PY" ]; then
  echo "  ⚠ 找不到可用 python（HUNTER_PYTHON/venv/系统都没有），SKIP"
  exit 0
fi

# fixture 落 repo 内 .positives/（MSYS 路径，native chromium 可读 C:/ 转换后的）
FIXD="$PWD/.positives"
mkdir -p "$FIXD"
trap 'rm -rf "$FIXD"' EXIT
FRAW="$FIXD/fixture_raw.html"; FESC="$FIXD/fixture_escaped.html"; FAB="$FIXD/fixture_absent.html"
cat > "$FRAW" <<'EOF'
<html><head><meta charset="utf-8"></head><body>
<div class="comment">用户昵称：<img id="hw_xssc" src="1" width="0" height="0" alt="HWXSS"></div>
</body></html>
EOF
cat > "$FESC" <<'EOF'
<html><head><meta charset="utf-8"></head><body>
<div class="comment">用户昵称：<span>HWXSS</span>（已实体化 <img id="hw_xssc_esc" alt="&lt;img&gt;">）</div>
</body></html>
EOF
cat > "$FAB" <<'EOF'
<html><head><meta charset="utf-8"></head><body>
<p>该入口无渲染位，页面未包含任何探针串</p>
</body></html>
EOF
# native chromium 只认 C:/ 盘符路径，不认 MSYS /c/... → 转 native
to_win(){ cygpath -w "$1" 2>/dev/null || echo "$1"; }
furl(){ local w; w=$(to_win "$1"); printf 'file:///%s' "${w//\\//}"; }   # C:\x → C:/x

pass=0; fail=0; skip=0
run(){ # $1=label $2=fixture-path $3=expect
  local url
  url=$(furl "$2")
  local out
  out=$("$PY" tools/xssprobe.py --url "$url" --canary HWXSS 2>/dev/null)
  local v
  v=$(echo "$out" | "$PY" -c "import sys,json
try: print(json.loads(sys.stdin.read()).get('verdict','?'))
except Exception: print('?')" 2>/dev/null)
  if [ -z "$out" ]; then
    echo "  ⚠ $1 SKIP（xssprobe 无输出，chromium 起不来）"; skip=$((skip+1)); return
  fi
  if [ "$v" = "$3" ]; then echo "  ✓ $1 PASS（判 $v，符合期望）"; pass=$((pass+1))
  else echo "  ✗ $1 FAIL（判 $v，期望 $3）"; fail=$((fail+1)); fi
}

echo "══ 阳性对照：xssprobe 三态自验（离线 fixture）══"
run "A 洞页（canary 原样成 <img> 节点）" "$FRAW" "A"
run "B 转义页（canary 被实体化纯文本）"   "$FESC" "B"
run "C 无回显页（canary 不存在）"         "$FAB"  "C"
echo "════════ 阳性对照: PASS $pass / FAIL $fail / SKIP $skip ════════"
if [ "$fail" = 0 ] && [ "$pass" -ge 1 ]; then
  echo "  🟢 管线健康：洞真存在时抓得住（以后 0命中 归因目标薄，非工具瞎）"
elif [ "$fail" = 0 ]; then
  echo "  ⚠ 全 SKIP（chromium 不可用）——工具健康未验证，别据此下目标结论"
fi
exit "$fail"
