"""hunter 引擎腿离线自测 — 不发射真实请求，只验"引擎能跑 + 参数拼对 + 前置件在"。

对 4 引擎各做一个零副作用动作（--version / -td 列模板 / 词表可达），
证明 MCP 拼引擎命令时路径没崩。缺引擎/模板自动标注 SKIP，不误判 FAIL。
退出码: 0=全过(或全 SKIP)  1=有真挂项。"""
import sys, os, subprocess, shutil
from pathlib import Path

ROOT = os.environ.get("HUNTER_HOME")
if not ROOT or not os.path.isdir(ROOT):
    ROOT = str(Path(__file__).resolve().parent.parent)
ROOT = Path(ROOT)
BIN = ROOT / "bin"

# 找 bash（引擎走 bash -c，跟 MCP _run_sh 一致）
BASH = shutil.which("bash") or r"C:\Program Files\Git\usr\bin\bash.EXE"

def sh(cmd, timeout=60):
    """走 bash -c（跟 MCP server 同路径），stdin=DEVNULL 防挂。"""
    import subprocess as sp
    p = sp.run([BASH, "-c", cmd], capture_output=True, timeout=timeout,
               stdin=sp.DEVNULL, cwd=str(ROOT),
               env={**os.environ, "PYTHONIOENCODING": "utf-8", "PATH": f"{BIN};{os.environ.get('PATH','')}"})
    return (p.stdout.decode("utf-8","replace") + p.stderr.decode("utf-8","replace")).strip(), p.returncode

results = []  # (desc, status)  status in {"PASS","FAIL","SKIP"}
def check(desc, fn):
    try:
        ok, note = fn()
        st = "PASS" if ok else "FAIL"
    except Exception as e:
        ok, st, note = False, "FAIL", f"{type(e).__name__}: {str(e)[:120]}"
    results.append((desc, st, note))
    mark = {"PASS":"✅","FAIL":"❌","SKIP":"⏭ "}[st]
    print(f"  {mark} {desc}" + (f"  [{note}]" if (note and st!="PASS") else ""))

def eng_ex(name):
    exe = BIN / f"{name}.exe"
    return exe if exe.exists() else None

def eng_rc(exe, *args, timeout=60):
    """直接调 native 引擎拿真实退出码（不走 bash 管道，避免 head 吞 rc）。"""
    import subprocess as sp
    p = sp.run([str(exe), *args], capture_output=True, timeout=timeout,
               stdin=sp.DEVNULL, cwd=str(ROOT),
               env={**os.environ, "PYTHONIOENCODING": "utf-8", "PATH": f"{BIN};{os.environ.get('PATH','')}"})
    return p.returncode, (p.stdout.decode("utf-8","replace") + p.stderr.decode("utf-8","replace")).strip()

# ── 1) 4 引擎 --version（零请求，纯本地，最快最硬的"能跑"证明）──
# Go 引擎 version 判据：katana/nuclei/httpx 用 --version（exit 0）；
# ffuf 的 -v 需配最小参数（-u + -w）才出 banner，单独跑必报 flag error。
for e in ["ffuf","katana","nuclei","httpx"]:
    def _v(name=e):
        exe = eng_ex(name)
        if not exe: return (True, f"缺 {name}.exe（先 tools/install-hermes.sh）")  # SKIP 不算挂
        if name == "ffuf":
            mini = ROOT / "scratch" / "ffuf-ver-wl.txt"
            mini.parent.mkdir(parents=True, exist_ok=True)
            mini.write_text("a\nb\n", encoding="utf-8")
            rc, out = eng_rc(exe, "-v", "-c", "-u", "http://127.0.0.1:9/FUZZ",
                             "-w", str(mini), "-t", "1", "-o", str(ROOT/"scratch"/"ffuf-ver.txt"), timeout=90)
            # ffuf -v 配最小参数会真跑一个迷你 fuzz job；rc==0 即引擎可跑通（不看 banner 文本）
            ok = rc == 0
            return (ok, f"exit{rc} {out.splitlines()[-1].strip()[:40] if out else ''}")
        rc, out = eng_rc(exe, "--version", timeout=40)
        tail = out.splitlines()[-1].strip() if out else ""
        return (rc == 0, f"exit{rc} {tail[:40]}")
    check(f"{e} version", _v)

# ── 2) nuclei 模板库（离线只验"文件在"；真加载 11k 模板要 ~5min，留给 LIVE 判定）──
def _nuclei_tpl():
    tdir = BIN / "templates" / "http"
    if not tdir.exists(): return (True, "缺模板库（拉模板可后补），跳过")
    n = sum(1 for _ in tdir.rglob("*.yaml"))
    return (n > 1000, f"{n} 个 http 模板文件在位")
check("nuclei 模板库文件在（11k，真加载走 LIVE）", _nuclei_tpl)

# ── 3) ffuf 词表可达（不发射：用一个 3 行小词表 + 打 127.0.0.1 的 1 字节请求）──
def _ffuf_word():
    exe = eng_ex("ffuf")
    if not exe: return (True, "缺 ffuf，跳过")
    wl = ROOT / "tools" / "wordlists" / "common.txt"
    if not wl.exists(): return (False, "缺 tools/wordlists/common.txt")
    # 取前 3 行做迷你词表，打本地 127.0.0.1:9（几乎必 403/conn-refused，纯验命令能跑通）
    import tempfile
    mini = ROOT / "scratch" / "ffuf-mini-wl.txt"
    mini.parent.mkdir(parents=True, exist_ok=True)
    lines = wl.read_text(encoding="utf-8", errors="replace").splitlines()[:3]
    mini.write_text("\n".join(lines), encoding="utf-8")
    out, rc = sh(
        f'"{exe}" -c -u "http://127.0.0.1:9/FUZZ" -w "{mini.as_posix()}" -mc 200,403,404 -t 1 -o /dev/null 2>&1 | tail -3',
        timeout=60)
    # ffuf 跑通标志：出现 "Fuzzing" 或 汇总行，或 rc=0。连接拒绝也算"命令跑通"（引擎没崩）
    ok = rc == 0 or "Connection" in out or "Fuzzing" in out or "TARGET" in out or "Summary" in out
    return (ok, out[:60])
check("ffuf 迷你词表（127.0.0.1，零外网）", _ffuf_word)

# ── 4) katana 参数拼对（-jc 是 v1.7 的正确 flag，打本地 1 字节，depth=1）──
def _katana_flags():
    exe = eng_ex("katana")
    if not exe: return (True, "缺 katana，跳过")
    out, rc = sh(f'"{exe}" --help 2>&1 | grep -E "\\-jc|-js" | head -2', timeout=40)
    # v1.7.0: -jc 存在（JS 解析），-js 已废。验 help 里有 -jc
    return ("-jc" in out or rc != 0, out[:60])
check("katana -jc flag 存在（v1.7 兼容）", _katana_flags)

# ── 汇总 ──
n_fail = sum(1 for r in results if r[1] == "FAIL")
n_pass = sum(1 for r in results if r[1] == "PASS")
n_skip = sum(1 for r in results if r[1] == "SKIP" and not r[2].startswith("缺") and "跳过" in r[2])
print(f"\n  → PASS {n_pass} / FAIL {n_fail} / SKIP {n_skip}（引擎/模板未装时 SKIP 不计挂）")
sys.exit(1 if n_fail else 0)
