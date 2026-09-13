#!/usr/bin/env bash
# download-templates.sh — nuclei 模板本地库（bin/templates/）
# 通道策略（实测）：国内 codeload 的 zip 常断流；api.github.com 的 tarball 重定向也落 codeload，
# 但 tar.gz 支持断点续传（zip 不支持 range）→ curl -C - 续传 + 重试循环，断了接着拉不重来。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DST="$HERE/bin/templates"
SCRATCH="$HERE/scratch"
mkdir -p "$SCRATCH" "$HERE/bin"
OUT="$SCRATCH/nuclei-templates.tar.gz"
URL="https://api.github.com/repos/projectdiscovery/nuclei-templates/tarball/main"

# 已就位（>100 个 http 模板）就跳
if [ -d "$DST/http" ] && [ "$(find "$DST/http" -name '*.yaml' 2>/dev/null | wc -l)" -gt 100 ]; then
  echo "模板已就位（$(find "$DST/http" -name '*.yaml' | wc -l) 个 http 模板），跳过"
  exit 0
fi

rm -rf "$DST" "$OUT"
echo "拉模板（断点续传，最多 60 轮）…"
ok=0
for i in $(seq 1 60); do
  curl -sk4L -C - -m 300 -o "$OUT" "$URL" 2>/dev/null
  if gunzip -t "$OUT" 2>/dev/null; then ok=1; echo "第 $i 轮拉完（$(wc -c < "$OUT" | tr -d ' ') B）"; break; fi
  echo "第 $i 轮断在 $(wc -c < "$OUT" 2>/dev/null | tr -d ' ') B，3s 后续传…"
  sleep 3
done

if [ "$ok" != "1" ]; then
  echo "❌ 模板没拉全（网络持续受限）。不影响其他 7 腿；nuclei 可后补：重跑本脚本。"
  exit 1
fi

# 解压并摊平：tarball 顶层是一层壳目录（nuclei-templates-*/），内容提到 $DST/
mkdir -p "$DST"
tar -xzf "$OUT" -C "$DST" 2>/dev/null
sh="$(find "$DST" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
if [ -n "$sh" ]; then
  # 把壳里内容上移一层，删壳
  ( cd "$DST" && find "$(basename "$sh")" -mindepth 1 -maxdepth 1 -exec mv {} . \; ) 2>/dev/null
  rm -rf "$sh"
fi
echo "✓ 模板就位: $(find "$DST/http" -name '*.yaml' 2>/dev/null | wc -l) 个 http 模板 → $DST/http"
