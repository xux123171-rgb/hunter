#!/usr/bin/env bash
# download-templates.sh — nuclei 模板本地库（bin/templates/）
# 通道实测（2026-09-13，国内）：
#   codeload tarball + 代理/TUN：~43KB/s，7~10MB 一轮 ~4 分钟，可整拉成功（首选）
#   git clone 原生 github：TUN 下 packfile 常被掐（fetch-pack 报错），无代理时常断（兜底）
#   ghproxy.net：时好时坏（再兜底）
# 策略：整拉重试 → git clone → ghproxy clone，命中即把仓/包挪进 bin/templates。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DST="$HERE/bin/templates"
SCRATCH="$HERE/scratch"
mkdir -p "$SCRATCH" "$HERE/bin"
OUT="$SCRATCH/nuclei-templates.tar.gz"
CODELOAD="https://codeload.github.com/projectdiscovery/nuclei-templates/legacy.tar.gz/refs/heads/main"
REPO="$SCRATCH/nuclei-templates-repo"

# 已就位（>100 个 http 模板）就跳
if [ -d "$DST/http" ] && [ "$(find "$DST/http" -name '*.yaml' 2>/dev/null | wc -l)" -gt 100 ]; then
  echo "模板已就位（$(find "$DST/http" -name '*.yaml' | wc -l) 个 http 模板），跳过"
  exit 0
fi

rm -rf "$DST" "$REPO" "$OUT"

echo "① codeload 整拉重试（建议开代理/TUN，~4min/轮，最多 6 轮）…"
ok=0
for i in $(seq 1 6); do
  curl -sk4L -m 500 -o "$OUT" "$CODELOAD" 2>/dev/null
  if gunzip -t "$OUT" 2>/dev/null; then
    ok=1; echo "  ✓ 第 $i 轮拉完（$(wc -c < "$OUT" | tr -d ' ') B）"
    break
  fi
  echo "  第 $i 轮不完整（$(wc -c < "$OUT" 2>/dev/null | tr -d ' ') B），5s 后重拉…"
  sleep 5
done

if [ "$ok" != "1" ]; then
  echo "② git clone 兜底（原生 → ghproxy，最多 4 轮）…"
  for i in $(seq 1 4); do
    rm -rf "$REPO"
    if git clone --depth 1 -q https://github.com/projectdiscovery/nuclei-templates.git "$REPO" 2>/dev/null && [ -d "$REPO/http" ]; then ok=1; echo "  ✓ 原生 github"; break; fi
    if git clone --depth 1 -q "https://ghproxy.net/https://github.com/projectdiscovery/nuclei-templates.git" "$REPO" 2>/dev/null && [ -d "$REPO/http" ]; then ok=1; echo "  ✓ ghproxy"; break; fi
    sleep 5
  done
fi

if [ "$ok" != "1" ]; then
  echo "❌ 全通道失败（网络受限）。不影响其他 7 腿；开代理/TUN 后重跑本脚本。"
  exit 1
fi

# 落到 bin/templates：tarball 解一层壳；git 仓直接挪内容
if [ -f "$OUT" ] && [ "$ok" = "1" ] && [ ! -d "$REPO" ]; then
  mkdir -p "$DST"
  tar -xzf "$OUT" -C "$DST" 2>/dev/null
  sh="$(find "$DST" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
  if [ -n "$sh" ]; then
    ( cd "$DST" && find "$(basename "$sh")" -mindepth 1 -maxdepth 1 -exec mv {} . \; 2>/dev/null; rm -rf "$sh" )
  fi
else
  mkdir -p "$DST"
  shopt -s dotglob
  mv "$REPO"/* "$DST"/ 2>/dev/null
  rm -rf "$REPO"
fi
rm -f "$OUT"
echo "✓ 模板就位: $(find "$DST/http" -name '*.yaml' 2>/dev/null | wc -l) 个 http 模板 → $DST/http"
