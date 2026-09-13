#!/usr/bin/env bash
# download-templates.sh — nuclei 模板本地库（bin/templates/）
# 通道策略（按"无代理可用性"排序，2026-09-13 实测）：
#   ① hunter 仓库 Release 资产 API 接口（api.github.com，国内通常直连不用代理，
#      支持 Range 断点续传；私有仓必须带 token——读 .hunter-token 或 HUNTER_GITHUB_TOKEN）
#   ② codeload 整拉（开代理/TUN 时 ~43KB/s，10MB 一轮 ~4min）
#   ③ git clone 原生 github → ghproxy（最后兜底）
# 注：Release 附件匿名 URL（releases/download/...）对私有仓库必 404，必须走带 token 的 API 接口。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DST="$HERE/bin/templates"
SCRATCH="$HERE/scratch"
mkdir -p "$SCRATCH" "$HERE/bin"
OUT="$SCRATCH/nuclei-templates.tar.gz"
REPO="$SCRATCH/nuclei-templates-repo"
ASSET_API="https://api.github.com/repos/xux123171-rgb/hunter/releases/assets/561502513"
CODELOAD="https://codeload.github.com/projectdiscovery/nuclei-templates/legacy.tar.gz/refs/heads/main"

# 已就位（>100 个 http 模板）就跳
if [ -d "$DST/http" ] && [ "$(find "$DST/http" -name '*.yaml' 2>/dev/null | wc -l)" -gt 100 ]; then
  echo "模板已就位（$(find "$DST/http" -name '*.yaml' | wc -l) 个 http 模板），跳过"
  exit 0
fi

# ① 通道：带 token 读 .hunter-token（gitignore）或 HUNTER_GITHUB_TOKEN
TOK="${HUNTER_GITHUB_TOKEN:-}"
[ -z "$TOK" ] && [ -f "$HERE/.hunter-token" ] && TOK="$(tr -d '[:space:]' < "$HERE/.hunter-token")"
AUTH=(); [ -n "$TOK" ] && AUTH=(-H "Authorization: Bearer $TOK")

rm -rf "$DST" "$REPO" "$OUT"
how=""

if [ -n "$TOK" ]; then
  echo "① Release 资产 API（带 token，无代理可直连，断点续传；无代理时 ~1KB/s，9.8MB 需数小时，挂着拉完即可）…"
  for i in $(seq 1 40); do
    CUR="$(wc -c < "$OUT" 2>/dev/null | tr -d ' ')"
    RANGE=(); [ -n "$CUR" ] && RANGE=(-C "$CUR")
    curl -sk4L -m 600 "${AUTH[@]}" "${RANGE[@]}" -o "$OUT" "$ASSET_API" 2>/dev/null
    gunzip -t "$OUT" 2>/dev/null && { how="release-api"; echo "  ✓ 拉完（$(wc -c < "$OUT"|tr -d ' ') B，第 $i 轮）"; break; }
    echo "  已有 $(wc -c < "$OUT" 2>/dev/null | tr -d ' ') B，3s 后续拉…"
    sleep 3
  done
fi

# ② codeload 整拉（开代理时最快）
if [ -z "$how" ]; then
  echo "② codeload 整拉重试（建议开代理/TUN）…"
  rm -f "$OUT"
  for i in 1 2; do
    curl -sk4L -m 500 -o "$OUT" "$CODELOAD" 2>/dev/null
    if gunzip -t "$OUT" 2>/dev/null; then how="codeload"; echo "  ✓ 第 $i 轮拉完"; break; fi
    sleep 5
  done
fi

# ③ git clone（最后兜底）
if [ -z "$how" ]; then
  echo "③ git clone 兜底（原生 → ghproxy）…"
  for i in 1 2; do
    rm -rf "$REPO"
    if git clone --depth 1 -q https://github.com/projectdiscovery/nuclei-templates.git "$REPO" 2>/dev/null && [ -d "$REPO/http" ]; then how="git"; break; fi
    if git clone --depth 1 -q "https://ghproxy.net/https://github.com/projectdiscovery/nuclei-templates.git" "$REPO" 2>/dev/null && [ -d "$REPO/http" ]; then how="ghproxy-git"; break; fi
    sleep 5
  done
fi

if [ -z "$how" ]; then
  echo "❌ 全通道失败。不影响其他 7 腿。补救：开代理/TUN 后重跑；或给 .hunter-token 放个有效 token 再跑（走①无代理通道）。"
  exit 1
fi

# 落到 bin/templates：tarball 解一层壳；git 仓直接挪内容
mkdir -p "$DST"
if [ "$how" = "git" ] || [ "$how" = "ghproxy-git" ]; then
  shopt -s dotglob
  mv "$REPO"/* "$DST"/ 2>/dev/null
  rm -rf "$REPO"
else
  tar -xzf "$OUT" -C "$DST" 2>/dev/null
  sh="$(find "$DST" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
  if [ -n "$sh" ]; then
    ( cd "$DST" && find "$(basename "$sh")" -mindepth 1 -maxdepth 1 -exec mv {} . \; 2>/dev/null; rm -rf "$sh" )
  fi
fi
echo "✓ 模板就位（通道: $how）: $(find "$DST/http" -name '*.yaml' 2>/dev/null | wc -l) 个 http 模板 → $DST/http"
