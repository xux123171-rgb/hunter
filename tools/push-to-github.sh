#!/usr/bin/env bash
# hunter push-to-github.sh — 一键把本项目推到你的 GitHub 私有仓库（P 方式）
# 用法（在项目根）：
#   1) 把 GitHub 生成的 Personal Access Token 存进本目录 .hunter-token（一行，勿进 git/聊天）
#   2) 指定仓库名（可选）：  REPO=hunter bash tools/push-to-github.sh hunter
#   3) 不指定则默认 hunter
# 依赖：curl + git。token 走 API 创建私有仓库，再用带 token 的 URL 推。全程 token 不打印。
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN_FILE="$HERE/.hunter-token"
REPO="${1:-hunter}"
BRANCH="master"

[ -f "$TOKEN_FILE" ] || { echo "缺 $TOKEN_FILE"; echo "  GitHub → Settings → Developer settings → Tokens → 建一个 classic token，勾 repo 全权限，存到这里（一行）。"; exit 1; }
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
[ -n "$TOKEN" ] || { echo ".hunter-token 是空的"; exit 1; }
cd "$HERE"

# 1) 建私有仓库（若已存在，API 返回 422 则跳过）
API="https://api.github.com/user"
create_resp=$(curl -sk4 -m 30 -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-User-Agent: hunter-push" \
  -X POST "$API/repos" \
  -d "{\"name\":\"$REPO\",\"private\":true,\"description\":\"Compliance web-vuln hunting pipeline (SOP + toolchain + templates)\"}" \
  -w "\n@@HTTP=%{http_code}@@")
http=$(echo "$create_resp" | grep -oE '@@HTTP=[0-9]+' | sed 's/@@HTTP=//;s/@@*//')
echo "$create_resp" | grep -vE '^@@HTTP=' > /tmp/_hunter_repo.json
echo "== 创建仓库 API 返回 HTTP=$http =="
if [ "$http" = "422" ]; then echo "  仓库 $REPO 已存在，跳过创建（将直接推）"; fi
if [ "$http" = "401" ]; then echo "  401 鉴权失败：token 无效或过期，或 token 没有 repo 权限。检查后重存 .hunter-token。"; exit 1; fi

# 2) 推（带 token 的 URL，token 不打印；从 API 拿真实 owner，不靠 create 响应的 full_name）
LOGIN=$(curl -sk4 -m 20 -H "Authorization: Bearer ***" "https://api.github.com/user" \
  | grep -oE '"login": *"[^"]*"' | head -1 | cut -d'"' -f4)
FULL="${LOGIN:-xux123171-rgb}/$REPO"
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:$TOKEN@github.com/$FULL.git"
git push -u origin "$BRANCH" 2>&1 | sed "s/$TOKEN/***/g"
echo
echo "== 推完 remote（已把 token 从 URL 里抹掉）=="
git remote set-url origin "https://github.com/$FULL.git"
git remote -v
echo
echo "完成。仓库: https://github.com/$FULL (private)"
echo "token 在 .hunter-token（已被 .gitignore 挡出 git）。不再需要可删： rm .hunter-token"
