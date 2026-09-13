#!/usr/bin/env bash
# push-release.sh — 打全量发行版 + 传 GitHub Release 附件（两级包维护入口）
#
# 两种包：
#   full   hunter-full-vX.zip（~150MB，代码+引擎+模板）→ 引擎大版本更新时重打
#   templ  nuclei-templates.tar.gz（~10MB，仅模板）    → 官方模板更新时（几分钟拉完，比全量快 15 倍）
#
# 用法：
#   bash tools/push-release.sh full v0.3        # 打全量包 + 建/更新 Release v0.3 + 上传
#   bash tools/push-release.sh templ v0.3       # 打模板包 + 传（模板常单独更新）
# 前置：.hunter-token（或 HUNTER_GITHUB_TOKEN）有 releases 权限。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
KIND="${1:?用法: bash tools/push-release.sh full|templ <version>}"
VER="${2:?缺版本号，例: v0.3}"
TOK="${HUNTER_GITHUB_TOKEN:-}"
[ -z "$TOK" ] && [ -f ".hunter-token" ] && TOK="$(tr -d '[:space:]' < .hunter-token)"
[ -z "$TOK" ] && { echo "❌ 无 token（放 .hunter-token 或设 HUNTER_GITHUB_TOKEN）"; exit 1; }
API="https://api.github.com/repos/xux123171-rgb/hunter"

# ── 打包 ──
case "$KIND" in
  full)
    OUT="scratch/hunter-full-$VER.zip"
    echo "═══ 打全量包（排除 .git/.venv/scratch/__pycache__/.hunter-token）═══"
    if command -v zip >/dev/null 2>&1; then
      zip -rq "$OUT" . -x "*.git*" "*.venv*" "scratch/*" "*__pycache__*" ".hunter-token"
    else
      python - "$OUT" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
root = os.getcwd()
EXCL = {".git", ".venv", "scratch", "__pycache__"}
def skip(n):
    return n in EXCL or n == ".hunter-token"
cnt = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for dp, dn, fn in os.walk(root):
        dn[:] = [x for x in dn if not skip(x)]
        for f in fn:
            if skip(f): continue
            full = os.path.join(dp, f)
            z.write(full, os.path.relpath(full, root)); cnt += 1
print(f"  打包 {cnt} 文件 -> {out} ({os.path.getsize(out)/1024/1024:.0f}MB)")
PY
    fi
    [ -f "$OUT" ] || { echo "❌ 打包失败"; exit 1; }
    ;;
  templ)
    OUT="scratch/nuclei-templates.tar.gz"
    echo "═══ 打模板包（先确认 bin/templates 是最新的）═══"
    [ -d bin/templates/http ] || { echo "❌ 先拉模板（bash tools/download-templates.sh）"; exit 1; }
    tar -czf "$OUT" bin/templates
    echo "  模板包 $(du -h "$OUT"|cut -f1)"
    ;;
  *) echo "❌ KIND 只支持 full|templ"; exit 1;;
esac

# ── 建 Release（已存在则跳过）──
echo "═══ 确保 Release $VER ═══"
UPURL=$(python - "$TOK" "$API" "$VER" <<'PY'
import sys, json, urllib.request
tok, api, ver = sys.argv[1], sys.argv[2], sys.argv[3]
req = urllib.request.Request(f"{api}/releases/tags/{ver}",
    headers={"Authorization":f"Bearer {tok}","Accept":"application/vnd.github+json"})
try:
    with urllib.request.urlopen(req, timeout=30) as f:
        print(json.load(f)["upload_url"])
except urllib.error.HTTPError:
    body = json.dumps({"tag_name":ver,"name":ver,"body":"hunter 发行版"}).encode()
    req = urllib.request.Request(f"{api}/releases", data=body, method="POST",
        headers={"Authorization":f"Bearer {tok}","Content-Type":"application/json","Accept":"application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=30) as f:
        print(json.load(f)["upload_url"])
PY
)
echo "  upload_url: ${UPURL:0:80}..."

# ── 上传附件 ──
NAME="$(basename "$OUT")"
echo "═══ 上传 $NAME（$(du -h "$OUT"|cut -f1)，大文件走浏览器更快；命令行传开代理）═══"
curl -sk4L -m 7200 -X POST \
  -H "Authorization: Bearer $TOK" -H "Content-Type: application/octet-stream" \
  --data-binary "@$OUT" \
  "${UPURL/\{?name,label\}/?name=$NAME}" -w "\n上传 http=%{http_code} 速度=%{speed_download}B/s\n" 2>&1 | tail -2
echo
echo "完。新机器: 登录 github 下载 $NAME → 解压 → bash tools/install-hermes.sh"
