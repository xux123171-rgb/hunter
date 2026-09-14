#!/usr/bin/env bash
# hunt-recon.sh — 阶段1+2 一键侦察（零落地：只出摘要表，不下全量文件）
# 用法: bash hunt-recon.sh <domain> [slug]
# 产出: <HUNTER_SCRATCH|仓库>/scratch/<slug>/assets.md (子域+IP)  probe.md (活体指纹)
set -u
DOM="${1:?usage: hunt-recon.sh <domain> [slug]}"
SLUG="${2:-${DOM//./_}}"
# 产物根目录：默认落仓库内 scratch/（clone 即用）；HUNTER_SCRATCH 可覆盖（如本机指回 D:/research/scratch）
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${HUNTER_SCRATCH:-$HERE/scratch}/$SLUG"
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

echo "==> [$DOM] 阶段1: 子域枚举 (DoH批量200前缀; crt.sh 走 hunter-cli subs 自研补长尾)"
# 并行 20 路（否则 200 前缀 × 1.5s/发 ≈ 5min+；并行后 <30s。合规:DoH 查询不碰目标）
CT=$(for p in www app api wap m h5 admin oa mail portal test dev old shop new cms erp crm hr srm wms ebidding e bidding zhaobiao openapi open api2 v1 v2 mobile applet mp pay sms jk jiankang yuyue guahao register login sso iam id oss bucket storage cdn img static assets file download dcdn gw gateway svc web page site news bbs forum forum1 blog wiki help support faq contact about hr2 it info data bigdata ai iot edge cloud vc vc2 vpn ssl cert log syslog monitor zabbix grafana kibana jenkins gitlab git svn gitea harbor registry nexus maven pypi npm docker k8s kubernetes etcd redis mysql oracle db sql mssql postgres pg mssql2 ldap ad dc nfs ftp sftp s3 minio cos tos oss2 obs aso eip slb alb nlb clb waf ddos antiddos antiwebapp botshield botshield2 edgeone esa waf2 aegis lychee yun jhelper jkyy yym ydy pacs his emr lis rpms 120 114 95598 95518 400 800 100 200 300 4008008009 4001000 8009 5598 zgyy zyy tjyy tj 12345 12346 12347 11112 22223 33334 44445 55556 66667 77778 88889 99990; do
  echo "$p.$DOM"
done | xargs -P 20 -I{} sh -c 'ip=$(curl -sk4 -m 8 "https://dns.alidns.com/resolve?name={}&type=A" | grep -oE "\"type\":1,\"data\":\"[0-9.]+\"" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort -u | tr "\n" " "); [ -n "$ip" ] && echo "{} => $ip"')
CT=$(echo "$CT" | grep '=>' | cut -d' ' -f1 | sort -u)
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
curl -sk4 -m 15 -A "$UA" "https://www.$DOM/" -o "$OUT/_home.html" -w "www -> HTTP %{http_code} %{size_download}B ip=%{remote_ip}\n"
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
  # MCP 子进程兜底：某些 bash 环境(/usr/bin/curl 旧版)写文件失败/HTTPS 失败 → 管道重取 + http 回退（老站 https 死 http 活）
  hdr=$(curl -sk4 -m 12 -A "$UA" -o "$OUT/_b.html" -w "%{http_code} %{size_download}" "https://$sub/" 2>/dev/null)
  case "$hdr" in 000*|"") hdr=$(curl -sk4 -m 10 -A "$UA" -o "$OUT/_b.html" -w "%{http_code} %{size_download}" "http://$sub/" 2>/dev/null);; esac
  curl -sk4 -m 12 -A "$UA" -D "$OUT/_h.txt" -o /dev/null "https://$sub/" 2>/dev/null
  [ -s "$OUT/_h.txt" ] || curl -sk4 -m 10 -A "$UA" -D "$OUT/_h.txt" -o /dev/null "http://$sub/" 2>/dev/null
  code=$(echo "$hdr" | tail -1 | awk '{print $1}')
  sz=$(echo "$hdr" | tail -1 | awk '{print $2}')
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
