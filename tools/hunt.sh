#!/usr/bin/env bash
# hunt.sh — 一条命令走完 SOP 阶段 0-3（合规内可全自动的部分），产出侦察包
# 用法: bash hunt.sh <domain> [slug] [scope_md]
#   scope_md 可选：scope.md 路径（授权范围逐字），脚本阶段0生成占位、人工补全
# 阶段4(洞型测试)需要判断力(实锤判定/判死/绕过)，脚本只把目标面摊开给 Agent，由 Agent 按 SOP 逐型打。
set -u
DOM="${1:?usage: hunt.sh <domain> [slug] [scope_md]}"
SLUG="${2:-${DOM//./_}}"
SCOPE="${3:-}"
# 仓库根：HUNTER_DIR 显式 > 脚本自身所在目录的上一级（clone 到哪就在哪，不写死机器路径）
ROOT="${HUNTER_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SCR="$ROOT/scratch/$SLUG"; REP="$ROOT/reports/$SLUG"
mkdir -p "$SCR" "$REP"

VALIDATE=""
[ -n "$SCOPE" ] && VALIDATE=1

echo "############ hunter: $DOM (slug=$SLUG) ############"
echo "产物目录: $SCR  $REP"

# ---- 阶段0 范围/红线：人工填 scope.md，脚本只生成占位 ----
cat > "$SCR/scope.md" <<EOF
# 范围 & 红线 — $DOM
- 平台/项目: __填__
- 厂商/归属: __填__(逐字核对页脚ICP/备案号原文,不脑补)
- 奖励: __现金/积分__  定级: __CVSS v3.1/v4/平台自定__
- 授权范围: __逐字抄__
- 红线: 禁__扫描器/社工/内网/DDoS__  注入只证可读  越权读 ≤__N__组
EOF
echo "[阶段0] scope.md 占位已建 → 人工补全后 Agent 才往下打"

# ---- 阶段1 资产测绘 ----
echo; echo "==== 阶段1 资产测绘 ===="
bash "$ROOT/tools/hunt-recon.sh" "$DOM" "$SLUG" 2>&1 | sed 's/^/  /'
# 合并 recon 产物到 scratch
cp -f /d/research/scratch/$SLUG/_assets.md  "$SCR/assets.md"  2>/dev/null
cp -f /d/research/scratch/$SLUG/_probe.md   "$SCR/probe.md"   2>/dev/null
cp -f /d/research/scratch/$SLUG/_home_js.txt "$SCR/home_js.txt" 2>/dev/null

# 可选：crt.sh 引擎（自研 hunter-cli subs，补 DoH 前缀之外的长尾子域）
#   用法: bash tools/hunter-cli.sh subs $DOM
echo "  [提示] 长尾子域由 hunter-cli subs（DoH+crt.sh 自研）补，结果并入 assets.md"

# ---- 阶段2 活体普查(已含在 recon) + nuclei 模板扫(非破坏) ----
echo; echo "==== 阶段2/4 模板扫 ===="
NUCLEI="$ROOT/bin/nuclei.exe"
if [ -f "$SCR/assets.md" ] && [ -x "$NUCLEI" ]; then
  # 从活体 IP 里挑公网 IP，跑一遍低侵入面板/泄露模板（合规：非破坏、限速）
  grep -oE '(\| ?[^| ]+\.(com|cn|net|org|gov|sh|edu)[0-9.]*)' "$SCR/assets.md" 2>/dev/null | head
  echo "  nuclei 本地库扫(非破坏/限速): $NUCLEI -u <活资产URL> -t '$ROOT/bin/templates/http/misconfiguration' -severity critical,high -rl 10"
fi

# ---- 阶段3 面绘制 ----
echo; echo "==== 阶段3 面绘制 ===="
echo "  本地: $ROOT/bin/katana.exe -u https://www.$DOM/ -d 2 -jc -kf -ct 25"
echo "  摊开的端点 × 前置条件 × 参数矩阵 → 记到 $SCR/endpoints.md"

cat > "$SCR/endpoints.md" <<EOF
# 端点矩阵 — $DOM
| 端点 | 前置(cookie/签名) | 参数 | 可否枚举ID | 洞型候选 |
|---|---|---|---|---|
EOF

# ---- 阶段4 交给 Agent ----
echo; echo "############ 自动部分到此为止 ############"
echo "阶段4(洞型测试 严重→低) 需判断力：Agent 按 SOP 4.1→4.4 逐型打，"
echo "出实锤记 $REP/finding_<n>.md，判死记 $SCR/deadlines.md。"
echo "阶段5/6 过7问 + 出报告：见 tools/EXEC.md。"
ls -la "$SCR" "$REP"
