#!/usr/bin/env python3
"""hunter-mcp — 我们自己的挖洞 MCP 服务（脑子+腿全指向本项目，无第三方 MCP 依赖）

定位：
- 脑子 = sop/PLAYBOOK.md（主）/ sop/SOP.md（简版）+ references/（hunter_brain 工具按需取原文，含 ladder 判死梯子）
- 腿   = tools/（recon/probe/matrix/monitor 走自研 hunter-cli.sh；crawl/scan/fuzz 直调 bin/ 引擎带参数控制力；
          xss/accounts/apk 走自研 python 工具）
- 合规 = 限速（nuclei -rl 5 / ffuf -rate 5）、非破坏、payload 克制（SOP 约束，工具只做单点探测）

运行（stdio，由 MCP 宿主拉起）：
  <python> mcp/server.py
宿主注册（Hermes config.yaml，<repo> 换 clone 路径）：
  mcp_servers:
    hunter:
      command: "<repo>/mcp/.venv/Scripts/python.exe"
      args: ["<repo>/mcp/server.py"]
路径自动发现（跨机，不再写死某台机器）：
  HUNTER_HOME   仓库根（默认兜底 = 本机开发路径，别的机器需设）
  HUNTER_PYTHON 跑子进程的解释器（默认找 Hermes agent venv / PATH python）
  bash          自动探测 Git for Windows 常见安装位置

工具（11 个，全是我们自己的）：
  hunter_recon(domain)         阶段1+2 子域+官网扫+活体指纹（hunter-cli recon）
  hunter_probe(url)           阶段2 单点活体指纹（hunter-cli probe，纯 curl）
  hunter_crawl(url, depth)    阶段3 面绘制（katana 直调，depth 可配）
  hunter_scan(url, tags, severity, rate_limit)  阶段4 nuclei 本地库非破坏扫（0命中强制自检防假阴性）
  hunter_fuzz(url, wordlist, rate_limit)        阶段4 ffuf 限速 fuzz（-s -or 防旧文件假命中）
  hunter_matrix(slug, domain) 阶段4 开工必建：攻击面矩阵骨架（A1-A9×资产，三终态制）
  hunter_monitor(domain)      持续侦察：子域快照 diff，报新增/鬼资产
  hunter_xss(url, ...)       阶段4 存储XSS 三态判定（xssprobe，惰性<img>canary，--then 多步流）
  hunter_accounts(cmd, tag)   越权双邮箱账号（mailacct create/inbox/otp）
  hunter_apk(apk)             A'移动端线：apk 扫硬编码密钥+API基址（纯 stdlib 零 Java）
  hunter_brain(what)          取脑子：playbook/sop/gates/waf/ladder/race 原文
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("hunter")


def _root() -> Path:
    # 仓库根 = mcp/server.py 上两级。HUNTER_HOME 可显式覆盖（多副本场景）。
    # 不再写死任何一台机器的绝对路径——clone 到哪就在哪跑。
    env = os.environ.get("HUNTER_HOME")
    if env and Path(env).is_dir():
        return Path(env)
    return Path(__file__).resolve().parent.parent


ROOT = _root()
BIN = ROOT / "bin"
TOOLS = ROOT / "tools"
# 喂 bash -c 里调原生 Windows 引擎时要正斜杠路径；喂 _run_py/subprocess 用 str(Path)
def _win(p: Path) -> str:
    return str(p)

# Python 子进程视角：bash/curl 由 git 自带，PATH 兜底常见安装位置。
# 关键修正：shutil.which 可能命中 C:\Windows\System32\bash.exe（WSL 启动桩，
# 机器没装 Linux 时只打印 "Linux is not installed" 的 UTF-16 乱码，脚本根本没跑）。
# 因此先用 _is_real_bash 逐个验证候选，拒绝 WSL 桩，落到真 Git bash。
def _is_real_bash(p: str) -> bool:
    # WSL 桩：System32/bash.exe（90KB 左右）；真 Git bash：usr/bin/bash.EXE。
    # 只要不在 System32，且能正常 fork/echo，就当真 bash。
    if "system32" in p.lower():
        return False
    try:
        r = subprocess.run([p, "-c", "echo ok"], capture_output=True, timeout=8,
                           stdin=subprocess.DEVNULL, text=True)
        return r.returncode == 0 and "ok" in r.stdout
    except Exception:
        return False


def _which(name: str, *extra: str) -> str:
    cands = []
    p = shutil.which(name)
    if p:
        cands.append(p)
    cands.extend(extra)
    # 1) 先给能真跑的子进程候选挑（排除 WSL 桩）
    for cand in cands:
        if _is_real_bash(cand):
            return cand
    # 2) 都验不过就原样返回 PATH 命中的（旧行为兜底，别直接崩）
    if p:
        return p
    raise SystemExit(f"找不到可用的 {name}（真 Git bash；确认装了 Git for Windows，或设 HUNTER_HOME）")


def _discover_bash() -> str:
    # 自动探测本机实际 bash 位置（git-bash 可能装在用户目录，如 C:\Users\<u>\Git\...），
    # 不再写死任何一台机器的路径——全部从 USERPROFILE / Program Files 动态拼。
    home = os.environ.get("USERPROFILE", "")
    user_git = [f"{home}\\Git\\usr\\bin\\bash.EXE", f"{home}\\Git\\bin\\bash.EXE"] if home else []
    return _which("bash",
                  *user_git,
                  r"C:\Program Files\Git\usr\bin\bash.EXE",
                  r"C:\Program Files (x86)\Git\usr\bin\bash.EXE",
                  r"C:\Program Files\Git\bin\bash.EXE")


BASH = _discover_bash()
# 启动时自检：真 bash 要能 echo；WSL 桩会报 "Linux is not installed"。
try:
    _chk = subprocess.run([BASH, "-c", "echo __hunt_ok__"], capture_output=True,
                          timeout=8, stdin=subprocess.DEVNULL, text=True)
    if "__hunt_ok__" not in _chk.stdout:
        print(f"[hunter-mcp] WARNING bash 自检未通过: {BASH} -> {_chk.stdout[:80]!r}", file=__import__('sys').stderr)
except Exception as _e:
    print(f"[hunter-mcp] WARNING bash 自检异常: {_e}", file=__import__('sys').stderr)


def _venv_py() -> str:
    # Python 宿主（跑 xssprobe/mailacct 子进程）：
    # 优先 HUNTER_PYTHON 显式指定 → Hermes agent venv（含 playwright）→ PATH 上的 python
    p = os.environ.get("HUNTER_PYTHON")
    if p and Path(p).exists():
        return p
    la = os.environ.get("LOCALAPPDATA")
    if la:
        cand = Path(la) / "hermes" / "hermes-agent" / "venv" / "Scripts" / "python.exe"
        if cand.exists():
            return str(cand)
    return shutil.which("python") or "python"


VENV_PY = _venv_py()


def _run_sh(cmd: str, timeout: int = 300) -> str:
    # 关键: stdin=DEVNULL。MCP server 的 stdin 是 stdio 协议管道，子进程若继承它会挂住
    # （login bash 检测到 piped stdin 会 stall）→ 之前 probe/crawl 走 MCP 就 90s 超时的根因。
    # PYTHONIOENCODING=utf-8: Windows 原生 python 子进程 stdout 默认 GBK，统一钉 UTF-8 防中文乱码。
    env = dict(os.environ, PATH=f"{BIN};{os.environ.get('PATH','')}", PYTHONIOENCODING="utf-8")
    p = subprocess.run([BASH, "-c", cmd], capture_output=True, timeout=timeout,
                       stdin=subprocess.DEVNULL, cwd=str(ROOT), env=env)
    return (p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")).strip()


def _run_py(args: list, timeout: int = 300) -> str:
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    p = subprocess.run([VENV_PY, *args], capture_output=True, timeout=timeout,
                       stdin=subprocess.DEVNULL, cwd=str(ROOT), env=env)
    return (p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")).strip()


def _eng(name: str) -> str:
    exe = f"{BIN}\\{name}.exe"
    if not Path(exe).exists():
        raise SystemExit(f"缺 {name}.exe，先跑 tools/install-toolchain.sh")
    return exe


def _scratch(slug: str) -> str:
    # 产物根目录：与 CLI scratchdir() 同一套规则（tools/hunter-scratch.sh）：
    # HUNTER_SCRATCH 设了 = 该目标产物根直接用不叠 slug（CLI 与 MCP 两腿落同一目录，防 <slug>/<slug>）；
    # 未设 = <仓库根>/scratch/<slug>（clone 即用）。
    base = os.environ.get("HUNTER_SCRATCH")
    if base:
        d = base.rstrip("/")
    else:
        d = os.path.join(str(ROOT), "scratch", slug)
    Path(d).mkdir(parents=True, exist_ok=True)
    return d


def _slug_of(url: str) -> str:
    import re
    host = re.sub(r"[?/].*$", "", url.split("//")[-1]) if "//" in url else url
    return host.replace(".", "_")


# ---------------------------------------------------------------- 工具
@mcp.tool()
def hunter_recon(domain: str) -> str:
    """阶段1+2 一键侦察（自研腿）：子域枚举(DoH+crt.sh) + 官网源码扫(内网IP:端口/备案/JS) + 活体指纹普查。
    零落地——只看响应头/状态码/字节数。产物落 scratch/<slug>/，返回摘要。"""
    out = _run_sh(f"bash '{TOOLS.as_posix()}/hunter-cli.sh' recon {json.dumps(domain)}", timeout=600)
    return out[:20000]


@mcp.tool()
def hunter_probe(url: str) -> str:
    """阶段2 单点活体指纹（纯自研 curl，1 次请求）：status/Server/Set-Cookie/404指纹/WAF指纹。"""
    out = _run_sh(f"bash '{TOOLS.as_posix()}/hunter-cli.sh' probe {json.dumps(url)}", timeout=90)
    return out[:8000]


@mcp.tool()
def hunter_crawl(url: str, depth: int = 2, js: bool = True) -> str:
    """阶段3 面绘制（katana 直调）：爬端点+JS，depth 控量（默认2，合规）。返回端点数+前50条。"""
    out = _scratch(_slug_of(url))
    args = [f"-u", f"{url}", f"-d", str(int(depth)), f"-o", f"{out}\\katana_endpoints.txt"]
    if js:
        args.append("-jc")
    args.append("-ct"); args.append("2m")
    args.append("-silent")
    _run_sh(f'"{_eng("katana")}" ' + " ".join(json.dumps(a) for a in args), timeout=300)
    f = Path(out) / "katana_endpoints.txt"
    lines = f.read_text(encoding="utf-8", errors="replace").splitlines() if f.exists() else []
    head = "\n".join(lines[:50])
    return f"端点总数 {len(lines)}，前 50 条:\n{head}\n（全量存 {f}）"


@mcp.tool()
def hunter_scan(url: str, severity: str = "critical,high", tags: str = "exposed-panels,exposure,misconfig,auth-bypass,tech",
                rate_limit: int = 5) -> str:
    """阶段4 非破坏模板扫（nuclei 本地库 bin/templates，限速默认5，合规）：暴露面板/错误配置/认证绕过/技术栈。"""
    out = _scratch(_slug_of(url))
    tdir = f"{BIN}\\templates\\http"
    args = [f"-u", f"{url}", f"-t", f"{tdir}", f"-severity", f"{severity}",
            f"-tags", f"{tags}", f"-rate-limit", str(max(1, int(rate_limit))), "-c", "5",
            f"-o", f"{out}\\nuclei.txt"]
    _run_sh(f'"{_eng("nuclei")}" ' + " ".join(json.dumps(a) for a in args), timeout=600)
    f = Path(out) / "nuclei.txt"
    txt = f.read_text(encoding="utf-8", errors="replace") if f.exists() else ""
    hits = [l for l in txt.splitlines() if l.strip()]
    if not hits:
        # 0 命中必须自检 tag 拼写：nuclei 不认识的 tag 静默 0 命中=假阴性陷阱（huntlab 实战抓过）
        return "无命中（tags=" + tags + "）。⚠️ 报 0 命中前先核对：tag 是否 nuclei 合法名（exposed-panel≠exposed-panels），合法名列表见 bin/templates 模板头部；建议二次跑 -tags tech 确认技术栈可检出，否则本结果不可当『干净』证据。"
    return "\n".join(hits)[:20000]


@mcp.tool()
def hunter_fuzz(url: str, wordlist: str = "", rate_limit: int = 5) -> str:
    """阶段4 目录/端点 fuzz（ffuf 直调，限速默认5，合规）：url 里放 FUZZ 占位。
    默认词表 tools/wordlists/common.txt（隐藏路径/面板/泄露类，非破坏）；wordlist 可传自定。"""
    out = _scratch(_slug_of(url))
    wl = wordlist or f"{TOOLS}\\wordlists\\common.txt"
    args = [f"-u", f"{url}", f"-w", f"{wl}", f"-mc", "200,204,301,302,307,401,403,405",
            f"-rate", str(max(1, int(rate_limit))), "-t", "5",
            f"-o", f"{out}\\ffuf.txt", "-of", "json", "-or"]
    _run_sh(f'"{_eng("ffuf")}" -s ' + " ".join(json.dumps(a) for a in args), timeout=600)
    f = Path(out) / "ffuf.txt"
    if not f.exists():  # -or: 0 结果不建文件（防读旧文件假命中）
        return "无命中（ffuf 限速 5；-or 模式 0 结果不落盘，本结果可信为空。词表=tools/wordlists/common.txt 共 10 条，覆盖面测试建议传大 wordlist）"
    try:
        data = json.loads(f.read_text(encoding="utf-8", errors="replace") or "{}")
        rows = [f"[{r.get('status')} {r.get('length')}B] {r.get('url')}" for r in data.get("results", [])]
        return ("\n".join(rows) or "无命中")[:20000]
    except Exception as e:
        return f"ffuf 结果解析失败: {e}（原始文件 {f}）"


@mcp.tool()
def hunter_matrix(slug: str, domain: str = "") -> str:
    """阶段4 开工必建：攻击面矩阵骨架（A1-A9 可打面 × 活资产，三终态制）。
    矩阵不清空=无权宣布打完；判死前每资产须过最低三件套(scan+fuzz+crawl)或写可复核豁免。"""
    return _run_sh(f"bash '{TOOLS.as_posix()}/hunter-cli.sh' matrix {json.dumps(slug)} {json.dumps(domain or slug)}", timeout=30)


@mcp.tool()
def hunter_monitor(domain: str, slug: str = "") -> str:
    """持续侦察（快照 diff）：重跑子域+活体普查与上次快照对比，只报新增/下线资产。
    新增资产=忘下线的旧站(出洞重灾区)重点打；下线资产=鬼资产候选(站没了接口常还活)。"""
    return _run_sh(f"bash '{TOOLS.as_posix()}/hunter-cli.sh' monitor {json.dumps(domain)} {json.dumps(slug or domain)}", timeout=600)


@mcp.tool()
def hunter_xss(url: str, selector: str = "", label: str = "", submit_selector: str = "",
               canary: str = "HWXSS", post_back: str = "", then_steps: str = "") -> str:
    """阶段4 存储XSS 三态判定（自研 xssprobe，Playwright 元素级 canary，惰性<img>非破坏）：
    A=canary 渲染成活 DOM 节点(实锤，报) / B=被转义成纯文本(过滤生效，不报) / C=无回显(换入口)。
    selector=输入框CSS；label=按label文本；submit_selector=提交按钮；post_back=回显页；
    then_steps=提交后多步触发（分号分隔，如 "click=a.card;goto=#detail"——client-side 流必用）。"""
    cmd = [f"{TOOLS}\\xssprobe.py", "--url", url, "--canary", canary]
    if selector:
        cmd += ["--sel", selector]
    if label:
        cmd += ["--field", label]
    if submit_selector:
        cmd += ["--submit-sel", submit_selector]
    if post_back:
        cmd += ["--post-back", post_back]
    for step in [s for s in (then_steps or "").split(";") if s.strip()]:
        cmd += ["--then", step.strip()]
    return _run_py(cmd, timeout=180)[:6000]


@mcp.tool()
def hunter_accounts(cmd: str, tag: str = "hunter") -> str:
    """越权双账号通道（自研 mailacct，合规双邮箱，收件侧）：
    cmd=create 建2独立邮箱号 / inbox 读收件箱 / otp 提4~6位验证码 / domains 看可用域名。
    手机号账号在用户侧，不在此工具范围。"""
    if cmd not in ("create", "inbox", "otp", "domains"):
        return "cmd 只支持 create/inbox/otp/domains"
    return _run_py([f"{TOOLS}\\mailacct.py", cmd, "--tag", tag], timeout=180)[:6000]


@mcp.tool()
def hunter_apk(apk: str) -> str:
    """A'移动端线 ①②步（纯 stdlib 零 Java）：apk(zip)或解包目录 → 扫硬编码密钥
    (AK/SK/jwt/password/private key) + API 基址/内网域名(喂 A1 扩面 & L5 源站)。
    dex 方法级反编需 jadx(Java)=手工环节，本腿只吃文件内容特征。"""
    return _run_py([f"{TOOLS}\\apksecret.py", "scan", apk], timeout=120)[:8000]


@mcp.tool()
def hunter_brain(what: str = "sop") -> str:
    """取脑子（本项目方法论，按需读，MCP 自包含无需 skill）：
    playbook = 完整作战手册（铁律+6阶段+判死速查+截图配方，最全，默认先读这个）
    sop = SOP 简版 / gates = 影响门+合规深度封顶表 / waf = 合规绕过 / race = 业务逻辑+并发。"""
    mapping = {"playbook": ROOT / "sop" / "PLAYBOOK.md",
               "sop": ROOT / "sop" / "SOP.md",
               "gates": ROOT / "references" / "impact-priority-gates.md",
               "waf": ROOT / "references" / "waf-bypass.md",
               "ladder": ROOT / "references" / "death-escalation-ladder.md",
               "race": ROOT / "references" / "race-business-logic.md"}
    path = mapping.get(what, mapping["playbook"])
    try:
        # D2: 本地读文件不耗流量，放宽截断（原 20000 在 PLAYBOOK 长大后会截掉判死梯子/三件套 SOP 后半）
        return path.read_text(encoding="utf-8", errors="replace")[:60000]
    except FileNotFoundError:
        return f"找不到 {path}（设 HUNTER_HOME 指向项目根；可选: {list(mapping)}）"


if __name__ == "__main__":
    mcp.run()  # stdio
