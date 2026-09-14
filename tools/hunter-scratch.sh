# hunter-scratch.sh — ⑤ 产出目录统一解析（CLI 与 hunt-recon 都 source 它，保证两腿落同一目录）
# 用法: source tools/hunter-scratch.sh; OUT="$(scratchdir "$slug")"; mkdir -p "$OUT"
# 规则: HUNTER_SCRATCH 设了 = 该目标产物根，直接用不叠 slug（如 D:/scratch/vwcom）
#       未设 = 回退到 <本仓库根>/scratch/<slug>（仓库根 = 本文件所在 tools/ 的上级，跨机自发现）
_scratch_repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }
scratchdir() { # $1=slug
  local slug="$1"
  if [ -n "${HUNTER_SCRATCH:-}" ]; then echo "${HUNTER_SCRATCH%/}"
  else echo "$(_scratch_repo_root)/scratch/$slug"; fi
}
