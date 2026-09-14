#!/usr/bin/env bash
# hunt-recon.sh — 阶段1+2 一键侦察（零落地：只出摘要表，不下全量文件）
# 用法: bash hunt-recon.sh <domain> [slug]
# 产出: <HUNTER_SCRATCH|仓库>/scratch/<slug>/assets.md (子域+IP)  probe.md (活体指纹)
set -u
DOM="${1:?usage: hunt-recon.sh <domain> [slug]}"
SLUG="${2:-${DOM//./_}}"
# 产物根目录：默认落仓库内 scratch/（clone 即用）；HUNTER_SCRATCH 可覆盖（如本机指回 D:/research/scratch）
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ⑤ 产出目录解析：统一走 tools/hunter-scratch.sh（与 hunter-cli 共用一份，两腿同目录，防 <slug>/<slug> 叠层）
source "$HERE/tools/hunter-scratch.sh"
OUT="$(scratchdir "$SLUG")"
mkdir -p "$OUT"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36"

doh() { # ali DoH 解析 A，输出唯一 IP（强制IPv4，本机IPv6不稳）
  curl -sk4 -m 8 "https://dns.alidns.com/resolve?name=$1&type=A" \
    | grep -oE '"type":1,"data":"[0-9.]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' '
}
dohc() { # CNAME
  curl -sk4 -m 8 "https://dns.alidns.com/resolve?name=$1&type=CNAME" \
    | grep -oE '"type":5,"data":"[^"]+"' | sed 's/.*"data":"//;s/"//' | sort -u | tr '\n' ' '
}

# ⑧ 共享子域词表（~400 前缀，覆盖 大厂/legacy/dev/营销/支付/AI）+ 官网自动抽品牌主体词
# 与 hunter-cli subs 走同一份 tools/wordlists/subs.txt，两处不漂移
_WL="$HERE/tools/wordlists/subs.txt"; [ -f "$_WL" ] || _WL=""
_PFX=""; [ -n "$_WL" ] && _PFX=$(tr '\n' ' ' < "$_WL" | sed 's/ #.*//')
[ -z "$_PFX" ] && _PFX="www app api wap m h5 admin oa mail portal test dev old shop new cms erp crm hr srm"
# ⑧ 官网抽品牌/主体词（<title>/meta keywords 里 2~14 字母词，滤通用词）当专属前缀
_BALL=""
curl -sk4 -m 15 -A "$UA" "https://www.$DOM/" 2>/dev/null > "$OUT/_brand.html"
_BALL=$( { grep -oiE '<title>[^<]*' "$OUT/_brand.html" 2>/dev/null | sed 's/<title>//i'
           grep -oiE '<meta[^>]*(name|property)="(keywords|og:site_name)"[^>]*content="[^"]*"' "$OUT/_brand.html" 2>/dev/null | sed 's/.*content="//;s/"//' ; } \
  | tr '[:upper:]' '[:lower:]' | grep -oiE '[a-z][a-z0-9_-]{1,13}' \
  | grep -vixE '^(www|com|cn|org|net|co|shop|home|index|about|login|app|api|news|blog|m|h5|portal|service|center|store|market|platform|科技|有限|公司|集团)$' \
  | grep -vixE '^(a|an|the|of|in|for|and|to|is|on|com|cn)$' | sort -u | head -8 | tr '\n' ' ' )
[ -n "$_BALL" ] && echo "⑧ 官网自动抽品牌/主体词追加前缀: $_BALL"
_PFX="$_PFX $_BALL"
echo "==> [$DOM] 阶段1: 子域枚举 (DoH批量 $(echo $_PFX | wc -w) 前缀[共享词表+品牌词]; crt.sh 走 hunter-cli subs 自研补长尾)"
# 并行 20 路（合规:DoH 查询不碰目标）。前缀列表经文件传入，xargs -P20
# 前缀列表并行探活：喂完整子域 p.$DOM 给 xargs，{} 内联替换（MSYS 下 sh -c 的 positional 传参 _ "$DOM" 会丢前缀，只有 {} 稳）
CT=$(for p in $_PFX; do printf '%s.%s\n' "$p" "$DOM"; done | xargs -P 20 -I{} sh -c 'ip=$(curl -sk4 -m 8 "https://dns.alidns.com/resolve?name={}&type=A" | grep -oE "\"type\":1,\"data\":\"[0-9.]+\"" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort -u | tr "\n" " "); [ -n "$ip" ] && echo "{} => $ip"' 2>/dev/null)
CT=$(echo "$CT" | grep -E '^[a-z0-9.-]+ => ' | cut -d' ' -f1 | sort -u)
echo "$CT" > "$OUT/_subs_raw.txt"
echo "$CT" | grep -v '^$' | head -40
NSUB=$(echo "$CT" | grep -c '^' || true)
echo "子域总数(去重): $NSUB"

echo; echo "==> 各子域 IP (DoH)"
: > "$OUT/_assets.md"
printf '# 资产表 %s\n\n| 子域 | A记录 | CNAME |\n|---|---|---|\n' "$DOM" >> "$OUT/_assets.md"
while read -r sub; do
  [ -z "$sub" ] && continue
  a=$(doh "$sub"); c=$(dohc "$sub")
  [ -z "$a" ] && [ -z "$c" ] && continue
  printf '| %s | %s | %s |\n' "$sub" "${a:--}" "${c:--}" >> "$OUT/_assets.md"
done <<< "$CT"
cat "$OUT/_assets.md"

echo; echo "==> 阶段2: 官网源码扫 (内网IP:端口 / JS / 备案)"
# ③ 官方 curl -o/-D 在 MSYS 会写 0 字节坑 → 全走 shell 重定向 + wc -c 验存
curl -sk4 -m 15 -A "$UA" "https://www.$DOM/" > "$OUT/_home.html" 2>/dev/null
HSZ=$(wc -c < "$OUT/_home.html" 2>/dev/null | tr -d ' ')
echo "www -> ${HSZ:-0}B (shell 重定向验存，0B=真下不到而非 -o 假象)"
[ "${HSZ:-0}" -eq 0 ] && echo "⚠️ 首页 0 字节，后续 grep 结果不可信（站死或 WAF 盾页）"
grep -oE '(?:[0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{2,5})?' "$OUT/_home.html" | grep -vE '^(127\.0\.0\.1|0\.0\.0\.0)' | sort -u > "$OUT/_home_ips.txt"
echo "首页内网/公网 IP:端口 ->"; cat "$OUT/_home_ips.txt"; [ -s "$OUT/_home_ips.txt" ] && echo "  ^^^ 有内网面板候选"
grep -oE 'src="[^"]+\.js[^"]*"' "$OUT/_home.html" | sed 's/src="//;s/"//' | sort -u > "$OUT/_home_js.txt"
echo "JS 引用:"; cat "$OUT/_home_js.txt"
grep -oE '(沪|鲁|京|粤|苏|浙|皖|冀|豫|桂|湘|鄂|滇|黔|甘|新|藏|陕|晋|赣|蒙|宁|甘|青|琼|冀)?ICP备[0-9A-Za-z-]+' "$OUT/_home.html" | sort -u | head
grep -oiE '(备案|ICP)[^<]*' "$OUT/_home.html" | head -3

echo; echo "==> 阶段2: 活体指纹普查 (每个活子域各1次，只看头)"
: > "$OUT/_probe.md"
printf '# 活体普查 %s\n\n' "$DOM" >> "$OUT/_probe.md"
while read -r sub; do
  [ -z "$sub" ] && continue
  ip=$(doh "$sub"); [ -z "$ip" ] && continue
  case "$ip" in 127.*|10.*|192.168.*|172.16.*|172.17.*|172.31.*) echo "  $sub 内网IP $ip (跳过探活)"; continue;; esac
  # ③+C1 shell 重定向验存；https 死回退 http。正常 2 发/子域（body 1 发 + code/响应头 1 发合并）
  curl -sk4 -m 12 -A "$UA" "https://$sub/" > "$OUT/_b.html" 2>/dev/null
  BZ=$(wc -c < "$OUT/_b.html" 2>/dev/null | tr -d ' '); BZ="${BZ:-0}"
  proto=https
  [ "$BZ" -eq 0 ] && { curl -sk4 -m 10 -A "$UA" "http://$sub/" > "$OUT/_b.html" 2>/dev/null; BZ=$(wc -c < "$OUT/_b.html" 2>/dev/null | tr -d ' '); BZ="${BZ:-0}"; proto=http; }
  code=$(curl -sk4 -m 12 -A "$UA" "$proto://$sub/" -D "$OUT/_h.txt" -o /dev/null -w "%{http_code}" 2>/dev/null); code="${code:-000}"
  [ "$code" = "000" ] && { code=$(curl -sk4 -m 10 -A "$UA" "http://$sub/" -D "$OUT/_h.txt" -o /dev/null -w "%{http_code}" 2>/dev/null); code="${code:-000}"; proto=http; }
  sz="$BZ"
  srv=$(grep -iE '^server:' "$OUT/_h.txt" | head -1 | sed 's/^[Ss]erver: *//' | tr -d '
')
  cks=$(grep -iE '^set-cookie:' "$OUT/_h.txt" | head -1 | sed 's/^[Ss]et-[Cc]ookie: *//' | tr -d '\r' | cut -c1-60)
  waf=$(grep -oiE 'waf|触发.*防护|acw_tc|CT2-WAAP|安全验证|slide|captcha' "$OUT/_b.html" 2>/dev/null | sort -u | tr '\n' ';')
  echo "  [$code ${sz}B] $sub srv=[$srv] ck=[$cks] waf=[$waf]"
  printf '| %s | %s | %s | %s | %s | %s |\n' "$sub" "$code" "$sz" "$srv" "$cks" "${waf:--}" >> "$OUT/_probe.md"
done <<< "$CT"
printf '# 活体普查 %s\n\n| 子域 | 状态 | 字节 | Server | SetCookie | WAF指纹 |\n|---|---|---|---|---|---|\n' "$DOM" > "$OUT/_probe.md"
cat "$OUT/_probe.md"

echo; echo "==> 产出在 $OUT"
ls -la "$OUT"

# ── B1 目标价值预判：基于上面已探信号给"打/不打"定论（纯本地，不增请求）─────
# 判型经验（写进工具）：hb2h型(内网IP+公网可达)=出洞率最高 · 遗留无WAF=次 · 单域强WAF壳站/认证型=判死别磕
echo; echo "==> 目标价值预判（出洞率 + 判型 + 下一刀建议）"
# 信号1: 首页内网IP:端口（hb2h 候选）
INIP=$(grep -vE '^(127\.|0\.|255\.)' "$OUT/_home_ips.txt" 2>/dev/null | grep -E ':' | head -1)
# 信号2: 活子域里有多少带 WAF 指纹
WAFSUB=$(grep -cE 'acw_tc|yundunwaf|触发.*防护|CT2-WAAP' "$OUT/_probe.md" 2>/dev/null || echo 0)
LIVE=$(grep -c '^|' "$OUT/_probe.md" 2>/dev/null || echo 0)
if [ -n "$INIP" ]; then
  echo "  ★ hb2h 型（出洞率最高）：首页漏内网IP:端口 [$INIP] —— 直进阶段2，找公网可达管理面/SSRF 回显"
  echo "  下一刀: 该内网IP 同资产是否有公网端口; 有 SSRF 位则内网IP当靶标(合规高危实锤)"
else
  if [ "${LIVE:-0}" -le 2 ] && [ "${WAFSUB:-0}" -ge 1 ]; then
    echo "  ✗ 单域强WAF壳站（兰大一院型）：活子域≤2 且带WAF —— 未鉴权面大概率封顶，出洞率低"
    echo "  下一刀: 转 App/子域扩面(阶段1多渠道)，别磕 WAF"
  elif [ "${WAFSUB:-0}" -ge 3 ]; then
    echo "  ✗ 多子域但全线带WAF —— 走 waf-bypass 三手法(源站直连/业务逻辑面/race)，别硬刚"
  else
    echo "  ◆ 遗留/无WAF 候选（次优）：${LIVE} 个活子域、无强WAF指纹 —— 老系统逐个探未鉴权面"
    echo "  下一刀: 按 Server 指纹挑 IIS/Tomcat/老框架，试未鉴权 .ashx/.actuator/.git"
  fi
fi
echo "  （预判仅基于已探信号供决策；真要判死仍按 ladder 爬完 + 记 hunter dead）"
