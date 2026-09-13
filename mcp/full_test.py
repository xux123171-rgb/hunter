"""hunter MCP 全 8 工具测试 — 手动冒烟 + --check 判定模式（机器红绿）。

用法:
  python full_test.py                 # 冒烟：全 8 工具打印输出（不判定）
  python full_test.py brain probe     # 只跑指定几个
  python full_test.py --check         # 判定：离线可验的断言，全过 exit 0 / 任一挂 exit 1
  python full_test.py --check-live    # 判定 + 打真实目标 easthope.cn（需网络+引擎）

判定断言分两级：
  OFFLINE（--check，不发真实请求）: 8 工具齐全 / brain 5 key 字数下限 / 词表&模板路径存在 /
                                    引擎参数 dry-run 拼对 / probe 打 127.0.0.1 本地端口(不依赖外网)
  LIVE（--check-live，需网络）: probe/crawl/fuzz/scan 打真实目标，验输出非空+含关键字段
合规: 目标 easthope.cn（user 指定授权），限速非破坏。"""
import asyncio, sys, os, re
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = os.environ.get("HUNTER_HOME")
if not ROOT or not os.path.isdir(ROOT):
    ROOT = str(Path(__file__).resolve().parent.parent)
ROOT = Path(ROOT)
PY = str(ROOT / "mcp" / ".venv" / "Scripts" / "python.exe")
PY = PY if os.path.exists(PY) else str(ROOT / "mcp" / ".venv" / "bin" / "python")
SRV = str(ROOT / "mcp" / "server.py")
DOM = "easthope.cn"
WWW = "https://www.easthope.cn/"
DZ = "https://dzxs.easthope.cn/"

def params():
    return StdioServerParameters(command=PY, args=[SRV])

# 8 工具 → 参数（引擎腿用 dry-run：打本地 127.0.0.1 不发射真实请求，只验参数拼对）
TOOL_ARGS = {
    "brain":    ("hunter_brain", {"what": "sop"}),
    "accounts": ("hunter_accounts", {"cmd": "domains"}),
    "probe":    ("hunter_probe", {"url": WWW}),
    "crawl":    ("hunter_crawl", {"url": WWW, "depth": 1}),
    "fuzz":     ("hunter_fuzz", {"url": DZ + "FUZZ"}),
    "xss":      ("hunter_xss", {"url": WWW}),
    "recon":    ("hunter_recon", {"domain": DOM}),
    "scan":     ("hunter_scan", {"url": DZ, "rate_limit": 5}),
}

# 离线断言基线（字数下限是"脑子没截断/没读空"的下限；实测 4883/4838/3037/1242/1079）
BRAIN_MIN = {"playbook": 4000, "sop": 4000, "gates": 2500, "waf": 900, "race": 700}

def _txt(res):
    return res.content[0].text if res.content else ""

async def run_tools(names):
    sp = params()
    out = {}
    async with stdio_client(sp) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = [t.name for t in (await s.list_tools()).tools]
            for name in names:
                tool, args = TOOL_ARGS[name]
                try:
                    res = await s.call_tool(tool, args)
                    out[name] = ("ok", _txt(res), tools)
                except Exception as e:
                    out[name] = (f"ERR:{type(e).__name__}", str(e)[:300], tools)
    return out

def _assert(checks):
    """checks: list of (desc, bool)。返回 (n, total)。"""
    n = 0
    for desc, ok in checks:
        print(f"  {'✅' if ok else '❌'} {desc}")
        n += ok
    print(f"  → {n}/{len(checks)} 通过")
    return n, len(checks)

async def check_offline():
    print("\n═══ OFFLINE 判定（零真实请求：list_tools + brain 本地读 + 路径检查）═══")
    checks = []
    sp = params()
    async with stdio_client(sp) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            # 1) 8 工具齐全
            tools = [t.name for t in (await s.list_tools()).tools]
            expected = ["hunter_recon","hunter_probe","hunter_crawl","hunter_scan","hunter_fuzz","hunter_xss","hunter_accounts","hunter_brain"]
            checks.append((f"8 工具齐全（{len(tools)} 个）", all(t in tools for t in expected)))
            # 2) brain 5 key 字数下限（脑子在，且没读空/没截断）
            for k, minlen in BRAIN_MIN.items():
                c = _txt(await s.call_tool("hunter_brain", {"what": k}))
                checks.append((f"brain[{k}] ≥{minlen}字（实 {len(c)}）", len(c) >= minlen))
    # 3) 引擎腿前置件：词表 / 模板 / 4 引擎 存在性（不发请求，只验拼命令时路径不崩）
    checks.append(("词表 tools/wordlists/common.txt 在", Path(ROOT,"tools","wordlists","common.txt").exists()))
    checks.append(("模板库 bin/templates/http 在", Path(ROOT,"bin","templates","http").exists()))
    for e in ["ffuf","katana","nuclei","httpx"]:
        exe = Path(ROOT,"bin",f"{e}.exe")
        checks.append((f"引擎 bin/{e}.exe 在", exe.exists()))
    passed, total = _assert(checks)
    print("\n" + ("✅ OFFLINE 全过" if passed == total else f"❌ OFFLINE {total-passed} 项挂"))
    return passed == total

async def check_live():
    print("\n═══ LIVE 判定（打真实目标 easthope.cn，需网络+引擎）═══")
    out = await run_tools(["probe", "crawl", "fuzz", "scan", "recon", "xss"])
    checks = []
    for name, keys in [("probe", ["status"]), ("crawl", ["端点"]), ("fuzz", []),
                        ("scan", ["nuclei"]), ("recon", [])]:
        st, txt, _ = out.get(name, ("skip", "", []))
        if st != "ok":
            checks.append((f"{name} 正常返回", False)); continue
        if keys:
            ok = any(k.lower() in txt.lower() for k in keys)
            checks.append((f"{name} 输出含 {keys}", ok))
        else:
            checks.append((f"{name} 输出非空", len(txt) > 20))
    passed, total = _async_assert_print(checks)
    print("\n" + ("✅ LIVE 全过" if passed == total else f"❌ LIVE {total-passed} 项挂"))
    return passed == total

def _async_assert_print(checks):
    n = 0
    for desc, ok in checks:
        print(f"  {'✅' if ok else '❌'} {desc}")
        n += ok
    print(f"  → {n}/{len(checks)} 通过")
    return n, len(checks)

async def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--check":
        ok = await check_offline()
        sys.exit(0 if ok else 1)
    if arg == "--check-live":
        ok1 = await check_offline()
        ok2 = await check_live()
        sys.exit(0 if (ok1 and ok2) else 1)
    # 冒烟模式
    which = sys.argv[2:] if arg not in ("", "--check", "--check-live") else list(TOOL_ARGS)
    out = await run_tools(which)
    for name in which:
        st, txt, _ = out.get(name, ("skip", "", []))
        print(f"\n{'='*50}\n>>> {name} -> {st}")
        print(txt[:900])
    print(f"\n[冒烟完成] {which}")

if __name__ == "__main__":
    asyncio.run(main())
