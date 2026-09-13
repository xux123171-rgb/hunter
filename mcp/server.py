#!/usr/bin/env python3
"""hunter-mcp — 我们自己的挖洞 MCP 服务（脑子+腿全指向本项目，无第三方 MCP 依赖）

定位：
- 脑子 = sop/SOP.md + references/（hunter_brain 工具按需取原文）
- 腿   = tools/（recon/probe 走自研 hunter-cli.sh；crawl/scan/fuzz 直调 bin/ 引擎带参数控制力；
          xss/accounts 走自研 python 工具）
- 合规 = 限速（nuclei -rl 5 / ffuf -rate 5）、非破坏、payload 克制（SOP 约束，工具只做单点探测）

运行（stdio，由 MCP 宿主拉起）：
  <python> mcp/server.py
宿主注册（Hermes config.yaml）：
  mcp_servers:
    hunter:
      command: "C:\\Users\\ThinkPad\\AppData\\Local\\hermes\\hermes-agent\\venv\\Scripts\\python.exe"
      args: ["C:\\Users\\ThinkPad\\Documents\\src-xiaoxu\\hunter\\mcp\\server.py"]

工具（8 个，全是我们自己的）：
  hunter_recon(domain)         阶段1+2 子域+官网扫+活体指纹（hunter-cli recon）
  hunter_probe(url)           阶段2 单点活体指纹（hunter-cli probe，纯 curl）
  hunter_crawl(url, depth)    阶段3 面绘制（katana 直调，depth 可配）
  hunter_scan(url, tags, severity, rate_limit)  阶段4 nuclei 本地库非破坏扫
  hunter_fuzz(url, wordlist, rate_limit)        阶段4 ffuf 限速 fuzz（默认词表隐藏路径/泄露类）
  hunter_xss(url, ...)       阶段4 存储XSS 三态判定（xssprobe，惰性<img>canary）
  hunter_accounts(cmd, tag)   越权双邮箱账号（mailacct create/inbox/otp）
  hunter_brain(what)          取脑子：sop/gates/waf/race 原文
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("hunter")

ROOT = Path(os.environ.get("HUNTER_HOME", r"C:\Users\ThinkPad\Documents\src-xiaoxu\hunter"))
BIN = f"{ROOT}\\bin"
TOOLS = f"{ROOT}\\tools"

# Python 子进程视角：bash/curl 由 git 自带，PATH 兜底常见安装位置
def _which(name: str, *extra: str) -> str:
    p = shutil.which(name)
    if p:
        return p
    for cand in extra:
        if Path(cand).exists():
            return cand
    raise SystemExit(f"找不到 {name}（装 Git for Windows 或设 HUNTER_HOME 环境路径）")

BASH = _which("bash", r"C:\Users\ThinkPad\Git\usr\bin\bash.EXE")
VENV_PY = (r"C:\Users\ThinkPad\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe"
           if Path(r"C:\Users\ThinkPad\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe").exists()
           else shutil.which("python") or "python")


def _run_sh(cmd: str, timeout: int = 300) -> str:
    env = dict(os.environ, PATH=f"{BIN};{os.environ.get('PATH','')}")
    p = subprocess.run([BASH, "-lc", cmd], capture_output=True, timeout=timeout,
                       cwd=str(ROOT), env=env)
    return (p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")).strip()


def _run_py(args: list, timeout: int = 300) -> str:
    p = subprocess.run([VENV_PY, *args], capture_output=True, timeout=timeout, cwd=str(ROOT))
    return (p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")).strip()


def _eng(name: str) -> str:
    exe = f"{BIN}\\{name}.exe"
    if not Path(exe).exists():
        raise SystemExit(f"缺 {name}.exe，先跑 tools/install-toolchain.sh")
    return exe


def _scratch(slug: str) -> str:
    d = f"{ROOT}\\scratch\\{slug}"
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
    out = _run_sh(f"bash '{TOOLS.replace(chr(92), '/')}'/hunter-cli.sh recon {json.dumps(domain)}", timeout=600)
    return out[:20000]


@mcp.tool()
def hunter_probe(url: str) -> str:
    """阶段2 单点活体指纹（纯自研 curl，1 次请求）：status/Server/Set-Cookie/404指纹/WAF指纹。"""
    out = _run_sh(f"bash '{TOOLS.replace(chr(92), '/')}'/hunter-cli.sh probe {json.dumps(url)}", timeout=90)
    return out[:8000]


@mcp.tool()
def hunter_crawl(url: str, depth: int = 2, js: bool = True) -> str:
    """阶段3 面绘制（katana 直调）：爬端点+JS，depth 控量（默认2，合规）。返回端点数+前50条。"""
    out = _scratch(_slug_of(url))
    args = [f"{url}", f"-d", str(int(depth)), f"-o", f"{out}\\katana_endpoints.txt"]
    if js:
        args.append("-js")
    args.append("-silent")
    _run_sh(f'"{_eng("katana")}" ' + " ".join(json.dumps(a) for a in args), timeout=300)
    f = Path(out) / "katana_endpoints.txt"
    lines = f.read_text(encoding="utf-8", errors="replace").splitlines() if f.exists() else []
    head = "\n".join(lines[:50])
    return f"端点总数 {len(lines)}，前 50 条:\n{head}\n（全量存 {f}）"


@mcp.tool()
def hunter_scan(url: str, severity: str = "critical,high", tags: str = "exposed-panels,misconfig,auth-bypass",
                rate_limit: int = 5) -> str:
    """阶段4 非破坏模板扫（nuclei 本地库 bin/templates，限速默认5，合规）：暴露面板/错误配置/认证绕过。"""
    out = _scratch(_slug_of(url))
    tdir = f"{BIN}\\templates\\http"
    args = [f"-u", f"{url}", f"-t", f"{tdir}", f"-severity", f"{severity}",
            f"-tags", f"{tags}", f"-rl", str(max(1, int(rate_limit))), "-c", "5",
            f"-o", f"{out}\\nuclei.txt", "-silent"]
    _run_sh(f'"{_eng("nuclei")}" ' + " ".join(json.dumps(a) for a in args), timeout=600)
    f = Path(out) / "nuclei.txt"
    txt = f.read_text(encoding="utf-8", errors="replace") if f.exists() else ""
    return (txt.strip() or "无命中（nuclei 对 -u 全模板跑，注意模板数量大时耗时；可加 -tags 收窄）")[:20000]


@mcp.tool()
def hunter_fuzz(url: str, wordlist: str = "", rate_limit: int = 5) -> str:
    """阶段4 目录/端点 fuzz（ffuf 直调，限速默认5，合规）：url 里放 FUZZ 占位。
    默认词表 tools/wordlists/common.txt（隐藏路径/面板/泄露类，非破坏）；wordlist 可传自定。"""
    out = _scratch(_slug_of(url))
    wl = wordlist or f"{TOOLS}\\wordlists\\common.txt"
    args = [f"-u", f"{url}", f"-w", f"{wl}", f"-mc", "200,204,301,302,307,401,403,405",
            f"-rate", str(max(1, int(rate_limit))), "-t", "5", "-retries", "1",
            f"-o", f"{out}\\ffuf.txt"]
    _run_sh(f'"{_eng("ffuf")}" ' + " ".join(json.dumps(a) for a in args), timeout=600)
    f = Path(out) / "ffuf.txt"
    txt = f.read_text(encoding="utf-8", errors="replace") if f.exists() else ""
    return (txt.strip() or "无命中（ffuf 限速 5，全量词表跑完耗时较长；命中含 401/403 的越权面）")[:20000]


@mcp.tool()
def hunter_xss(url: str, selector: str = "", label: str = "", submit_selector: str = "",
               canary: str = "HWXSS", post_back: str = "") -> str:
    """阶段4 存储XSS 三态判定（自研 xssprobe，Playwright 元素级 canary，惰性<img>非破坏）：
    A=canary 渲染成活 DOM 节点(实锤，报) / B=被转义成纯文本(过滤生效，不报) / C=无回显(换入口)。
    selector=输入框CSS；label=按label文本；submit_selector=提交按钮；post_back=回显页。"""
    cmd = [f"{TOOLS}\\xssprobe.py", "--url", url, "--canary", canary]
    if selector:
        cmd += ["--sel", selector]
    if label:
        cmd += ["--field", label]
    if submit_selector:
        cmd += ["--submit-sel", submit_selector]
    if post_back:
        cmd += ["--post-back", post_back]
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
def hunter_brain(what: str = "sop") -> str:
    """取脑子（本项目方法论原文，按需读）：sop / gates(影响门+合规深度封顶表) / waf(合规绕过) / race(业务逻辑+并发)。"""
    mapping = {"sop": ROOT / "sop" / "SOP.md",
               "gates": ROOT / "references" / "impact-priority-gates.md",
               "waf": ROOT / "references" / "waf-bypass.md",
               "race": ROOT / "references" / "race-business-logic.md"}
    path = mapping.get(what, mapping["sop"])
    try:
        return path.read_text(encoding="utf-8", errors="replace")[:20000]
    except FileNotFoundError:
        return f"找不到 {path}（设 HUNTER_HOME 指向项目根）"


if __name__ == "__main__":
    mcp.run()  # stdio
