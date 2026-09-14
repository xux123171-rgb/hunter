#!/usr/bin/env bash
# hunter — 我们自己的统一入口（"脚"）。编排 阶段1→6，底层按需调 bin/ 里的引擎二进制。
# 第三方引擎(nuclei/ffuf/katana/httpx)只是被调用的依赖，不对外冒头。
# 用法: hunter <子命令> [参数]   (在项目根或任意处：export PATH=.../hunter/bin:$PATH 后直接 hunter ...)
#   子命令:
#     hunter subs   <domain>            阶段1 子域枚举(我们自研: 阿里DoH批量 + crt.sh)
#     hunter scope  <domain>            阶段0 生成 scope.md 占位
#     hunter recon  <domain> [slug]     阶段1+2 一键侦察(资产表+官网扫+活体指纹)
#     hunter probe  <url>               阶段2 活体指纹(纯自研 curl)
#     hunter crawl  <url>               阶段3 面绘制(调 katana)
#     hunter matrix <slug> [domain]     阶段4 开工: 攻击面矩阵骨架(A1-A9×资产,三终态制)
#     hunter monitor <domain> [slug]    持续侦察: 子域快照 diff(新增/鬼资产)
#     hunter scan   <url-or-listfile>   阶段2/4 模板扫(调 nuclei, 非破坏, 限速)
#     hunter fuzz   <url> [wordlist]    阶段4 目录/端点 fuzz(调 ffuf, 限速)
#     hunter report <slug>              阶段6 聚合报告骨架
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # 项目根
BIN="$HERE/bin"
ROOT="${HUNTER_DIR:-$HERE}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36"

have() { command -v "$1" >/dev/null 2>&1; }
# 引擎二进制优先用项目 bin/，其次系统 PATH
eng() { # eng <name> -> 解析可执行路径
  local n="$1"
  [ -x "$BIN/$n.exe" ] && { echo "$BIN/$n.exe"; return; }
  have "$n" && { echo "$(command -v "$n")"; return; }
  have "$n.exe" && { echo "$(command -v "$n.exe")"; return; }
  echo ""
}
# 原生 Windows 引擎(katana/nuclei/ffuf)只认 Windows 路径，不认 MSYS /c/... 绝对路径
# 且 cygpath -w 对相对路径不转 → 先绝对化再转 Windows；转不了退回原值
wp() { # wp <path> -> 原生引擎可用的 Windows 路径
  local p="$1" abs
  case "$p" in /*) abs="$p";; *) abs="$(pwd)/$p";; esac
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$abs" 2>/dev/null && return
  fi
  echo "$p"
}

# 本机 IPv6 不稳 → 所有 curl 强制 -4；DNS 走阿里 DoH
doh() { curl -sk4 -m 8 "https://dns.alidns.com/resolve?name=$1&type=A" \
  | grep -oE '"type":1,"data":"[0-9.]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' '; }

cmd_subs() { # 阶段1 自研子域枚举：DoH批量200前缀 + crt.sh CT
  local DOM="${1:?domain}"; local SLUG="${2:-${DOM//./_}}"
  local out="$ROOT/scratch/$SLUG"; mkdir -p "$out"
  echo "== hunter subs $DOM =="
  local PFX="www app api wap m h5 admin oa mail portal test dev old shop new cms erp crm hr srm wms ebidding e bidding zhaobiao openapi open api2 v1 v2 mobile applet mp pay sms jk jiankang yuyue guahao register login sso iam id oss bucket storage cdn img static assets file download gw gateway svc web page site news bbs blog wiki help support faq contact it info data bigdata ai iot edge cloud vpn ssl cert log monitor zabbix grafana jenkins gitlab git svn harbor registry nexus docker k8s etcd redis mysql oracle db sql mssql postgres ldap ad dc nfs ftp sftp s3 minio cos eip slb alb clb waf ddos antiddos botshield esa 120 114 400 800 95598 95518"
  : > "$out/_subs.txt"
  for p in $PFX; do
    local s="$p.$DOM"; local ip; ip=$(doh "$s")
    [ -n "$ip" ] && echo "$s  =>  $ip" >> "$out/_subs.txt"
  done
  echo "== DoH 前缀命中 =="; cat "$out/_subs.txt" 2>/dev/null
  echo "== crt.sh CT 长尾 =="
  curl -sk4 -m 40 "https://crt.sh/?d=$DOM&output=json" 2>/dev/null \
    | grep -oE '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | tr -d '*' | sort -u \
    | grep -vE '^\*$' | tee -a "$out/_subs_ct.txt" 2>/dev/null
  echo "→ 存 $out/_subs.txt (DoH) + _subs_ct.txt (crt.sh)"
}

cmd_scope() { # 阶段0 占位
  local DOM="${1:?domain}"; local SLUG="${2:-${DOM//./_}}"
  local out="$ROOT/scratch/$SLUG"; mkdir -p "$out"
  cat > "$out/scope.md" <<EOF
# 范围 & 红线 — $DOM
- 平台/项目: __填__
- 厂商/归属: __逐字核对页脚ICP原文__
- 奖励: __现金/积分__  定级: __CVSS v3.1/v4/平台__
- 授权范围: __逐字抄__
- 红线: 禁__扫描器/社工/内网/DDoS__  注入只证可读  越权读 ≤__N__组
EOF
  echo "scope.md 占位已建 → $out/scope.md (人工补全)"
}

cmd_recon() { # 阶段1+2 一键
  bash "$HERE/tools/hunt-recon.sh" "$1" "${2:-${1//./_}}"
}

cmd_probe() { # 阶段2 活体指纹（纯自研 curl）
  local URL="${1:?url}"
  echo "== hunter probe $URL =="
  local body
  # MSYS curl 的 -o 文件不可靠(写0字节)；body 用 -o - 走stdout，size 用 -w 拿
  body=$(curl -sk4 -m 12 -A "$UA" -o - -w "\n@@CODE=%{http_code}@@SZ=%{size_download}@@\n" "$URL" 2>/dev/null)
  local code sz
  code=$(echo "$body" | grep -oE '@@CODE=[0-9]+' | head -1 | sed 's/@@CODE=//;s/@@*//'); code="${code:-000}"
  sz=$(echo "$body" | grep -oE '@@SZ=[0-9]+' | head -1 | sed 's/@@SZ=//;s/@@*//'); sz="${sz:-0}"
  # 去尾两行标记
  body=$(echo "$body" | grep -vE '^@@CODE=' | grep -vE '^@@SZ=' | grep -vE '@@CODE=')
  echo "status=$code bytes=$sz"
  echo "--- waf/captcha 指纹 ---"; echo "$body" | grep -oiE 'waf|触发.*防护|acw_tc|CT2-WAAP|slide|captcha|安全验证' | sort -u | tr '\n' ';'; echo
  echo "--- 内网IP:端口 泄露 ---"; echo "$body" | grep -oE '(?:[0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{2,5})?' | grep -vE '^(127\.|0\.|255\.)' | sort -u
  echo "--- 框架指纹(cookie/js库) ---"; echo "$body" | grep -oiE 'PHPSESSID|JSESSIONID|ASP\.NET|Laravel|XSRF|vue|angular|react' | sort -u | tr '\n' ';'; echo
}

cmd_crawl() { # 阶段3 面绘制（调 katana）
  local URL="${1:?url}"; local K; K=$(eng katana)
  [ -z "$K" ] && { echo "缺 katana，先跑 tools/install-toolchain.sh"; return 1; }
  local SLUG="${HUNTER_SLUG:-$(echo "${URL#https://}" | sed 's/[/?].*//;s/./_/g')}"; local out="$ROOT/scratch/$SLUG"; mkdir -p "$out"
  echo "== hunter crawl $URL (katana) =="
  local O="$(wp "$out/katana_endpoints.txt")"
  "$K" -u "$URL" -d 2 -jc -kf all -aff -ct 2m -silent -o "$O" 2>/dev/null || \
    "$K" -u "$URL" -d 2 -jc -ct 2m -silent -o "$O"
  echo "→ 端点存 $out/katana_endpoints.txt"
}

cmd_scan() { # 阶段2/4 模板扫（调 nuclei，非破坏，限速；必用本地 bin/templates）
  local TGT="${1:?url 或 -l 列表文件}"; local N; N=$(eng nuclei)
  [ -z "$N" ] && { echo "缺 nuclei，先跑 tools/install-toolchain.sh"; return 1; }
  local SLUG="${HUNTER_SLUG:-x}"; local out="$ROOT/scratch/$SLUG"; mkdir -p "$out"
  # 本地模板库（install-toolchain 拉的）；没有则退回 nuclei 默认下载目录
  local TDIR="$ROOT/bin/templates/http"
  [ ! -d "$TDIR" ] && { echo "⚠️ 本地模板 $TDIR 不存在，退回 nuclei 默认模板(可能联网下载)"; TDIR=""; }
  echo "== hunter scan (nuclei, 限速10, 非破坏) =="
  local args=()
  if [ -f "$TGT" ]; then args+=("-l" "$(wp "$TGT")"); else args+=("-u" "$TGT"); fi
  [ -n "$TDIR" ] && args+=("-t" "$(wp "$TDIR")")
  args+=("-tags" "exposed-panels,misconfig,auth-bypass" -severity "critical,high" -rate-limit 10 -c 5 -o "$(wp "$out/nuclei.txt")")
  # 数组传参（不碰 eval），不吞 stderr —— 失败/模板缺失要看得见，别假阴性
  "$N" "${args[@]}" 2>&1 | grep -iE "nuclei v|no templates|FTL|ERR|found|probing" | head -6
  echo "→ 命中存 $out/nuclei.txt (0命中且见到日志=真干净; 无日志=假阴性)"
}

cmd_fuzz() { # 阶段4 目录/端点 fuzz（调 ffuf，限速；默认小词表）
  local URL="${1:?url含FUZZ}"; local WL="${2:-$HERE/tools/wordlists/common.txt}"; local F; F=$(eng ffuf)
  [ -z "$F" ] && { echo "缺 ffuf，先跑 tools/install-toolchain.sh"; return 1; }
  [ -f "$WL" ] || { echo "词表不存在 $WL (先造 tools/wordlists/common.txt)"; return 1; }
  local SLUG="${HUNTER_SLUG:-x}"; local out="$ROOT/scratch/$SLUG"; mkdir -p "$out"
  echo "== hunter fuzz $URL (ffuf, rate5, 非破坏) =="
  local WO="$(wp "$WL")" OF="$(wp "$out/ffuf.txt")"
  # ffuf 2.x：-s 静默(防进度条污染 stdout) -or 无结果不建文件(防读到旧/空文件误判) -of json
  "$F" -s -u "$URL" -w "$WO" -mc 200,204,301,302,307,401,403,405 -rate 5 -t 5 -or -of json -o "$OF" 2>&1 | grep -iE "Error|flag" | head -4
  if [ -f "$out/ffuf.txt" ]; then
    python - "$OF" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1],encoding="utf-8",errors="replace"))
    for r in d.get("results",[]):
        print(f"  [{r.get('status')} {r.get('length')}B] {r.get('url')}")
except Exception as e:
    print("  (结果解析失败:",e,")")
PY
    echo "→ 命中存 $out/ffuf.txt"
  else
    echo "→ 无命中（-or：0 结果不建文件；词表小可加自定 wordlist）"
  fi
}

cmd_monitor() { # 持续侦察：同 target 重跑 subs+probe，与上次快照 diff，只报"新增资产"（忘下线的旧站=出洞重灾区）
  local DOM="${1:?domain}"; local SLUG="${2:-${DOM//./_}}"
  local snapdir="$ROOT/scratch/$SLUG"; mkdir -p "$snapdir/snapshots"
  echo "== hunter monitor $DOM（快照 diff 模式，零落地）=="
  bash "$HERE/tools/hunt-recon.sh" "$DOM" "$SLUG" >/dev/null 2>&1
  local cur="$snapdir/snapshots/$(date +%Y%m%d_%H%M).subs"
  sort -u "$snapdir/_subs_raw.txt" > "$cur" 2>/dev/null || : > "$cur"
  local prev; prev=$(ls -1t "$snapdir/snapshots/"*.subs 2>/dev/null | sed -n 2p)
  if [ -z "$prev" ]; then
    echo "首次快照：$(wc -l < "$cur") 个活子域 → $cur（下次 monitor 起出 diff）"
  else
    echo "上次: $prev ($(wc -l < "$prev") 个)  本次: $(wc -l < "$cur") 个"
    echo "== 新增资产（重点打这些）=="; comm -13 "$prev" "$cur" | sed 's/^/  + /'
    echo "== 下线资产（鬼资产候选：站没了接口可能还活）=="; comm -23 "$prev" "$cur" | sed 's/^/  - /'
  fi
}

cmd_matrix() { # 阶段4 开工骨架：可打面 A1-A9 × 活资产 的矩阵表（判死/实锤/已试 三终态制）
  local SLUG="${1:?slug}"; local DOM="${2:-$SLUG}"
  local out="$ROOT/scratch/$SLUG"; mkdir -p "$out"
  local m="$out/matrix.md"
  [ -f "$m" ] && { echo "矩阵已存在 → $m（续格不重建）"; return 0; }
  { echo "# 攻击面矩阵 $DOM（每格终态：实锤→finding / 已试(记请求数+响应特征) / 判死(证据编号进 deadlines.md)）"
    echo
    echo "| 可打面\\资产 | 资产1 | 资产2 | 资产3 |"
    echo "|---|---|---|---|"
    for a in "A1子域多渠道(词表+CT+前端挖域+Wayback+GH+App+ICP姊妹域)" "A2公网IP非标端口" "A3CDN源站直连" "A4框架管理面(actuator/druid/nacos/swagger)" "A5泄露文件(.git/.env/.bak)" "A6认证流程(注册/找回/验证码/SSO)" "A7业务接口(未鉴权直读+双账号IDOR)" "A8输入回显(注入/上传/XSS)" "A9私有密钥AK/SK"; do
      echo "| $a | - | - | - |"
    done
    echo
    echo "> 判死前置=最低三件套(hunter_scan+hunter_fuzz+hunter_crawl)或可复核豁免；矩阵清空才准宣布打完。"
    echo "> 401/403 面先过 waf-bypass.md §0.5 绕过字典(≤3手法)再谈判死。"
  } > "$m"
  # 活资产列建议自动填（scratch 里有 _subs_raw/_assets 就拿来当列）
  local src; for src in "$out/_subs_raw.txt" "$out/assets.md"; do [ -f "$src" ] && { echo "可打资产源: $src（把列名改成真实活资产）"; break; }; done
  echo "矩阵骨架 → $m"
}

cmd_report() { # 阶段6 聚合骨架
  local SLUG="${1:?slug}"; local out="$ROOT/reports/$SLUG"; mkdir -p "$out"/{findings,pocs,evidence}
  [ -f "$out/SUMMARY.md" ] || cat > "$out/SUMMARY.md" <<EOF
# $SLUG — 汇总
(aggregate: findings/ 里已确认洞 → 自动生成矩阵; 阴性/缺头/版本 → evidence/recon_notes.md)
EOF
  echo "报告骨架已建 → $out (findings/ pocs/ evidence/)"; echo "跑完测试后人工/aggregate 填 SUMMARY"
}

# dispatch
case "${1:-help}" in
  subs) shift; cmd_subs "$@";;
  scope) shift; cmd_scope "$@";;
  recon) shift; cmd_recon "$@";;
  probe) shift; cmd_probe "$@";;
  crawl) shift; cmd_crawl "$@";;
  matrix) shift; cmd_matrix "$@";;
  monitor) shift; cmd_monitor "$@";;
  scan) shift; cmd_scan "$@";;
  fuzz) shift; cmd_fuzz "$@";;
  report) shift; cmd_report "$@";;
  help|*)
    grep -E '^#   |^#     ' "${BASH_SOURCE[0]}" | sed 's/^# *//' | head -20
    echo; echo "引擎依赖在 $BIN (nuclei/ffuf/katana/httpx，第三方底层，靠 tools/install-toolchain.sh 重建)"
    echo "本 CLI 的 subs/probe 为纯自研，不依赖任何第三方 MCP——所有子命令都能纯 bin/ 自跑。"
    ;;
esac
