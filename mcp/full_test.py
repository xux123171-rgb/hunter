"""hunter MCP 全 8 工具完整测试 — 按 argv 指定跑哪几个（分批发放，避前台超时）。
用法: python full_test.py brain accounts probe crawl fuzz xss
       python full_test.py recon
       python full_test.py scan
合规: 全部打 user 指定目标 easthope.cn，限速，非破坏。"""
import asyncio, sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

import os
from pathlib import Path

# 仓库根 = mcp/full_test.py 上两级（与 server.py 一致，不再写死任何一台机器路径）
ROOT = os.environ.get("HUNTER_HOME")
if not ROOT or not os.path.isdir(ROOT):
    ROOT = str(Path(__file__).resolve().parent.parent)

PY = str(Path(ROOT) / "mcp" / ".venv" / "Scripts" / "python.exe")
PY = PY if os.path.exists(PY) else str(Path(ROOT) / "mcp" / ".venv" / "bin" / "python")
SRV = str(Path(ROOT) / "mcp" / "server.py")
DOM = "easthope.cn"
WWW = "https://www.easthope.cn/"
DZ = "https://dzxs.easthope.cn/"

def params():
    return StdioServerParameters(command=PY, args=[SRV])

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

async def main():
    which = sys.argv[1:] or list(TOOL_ARGS)
    sp = params()
    async with stdio_client(sp) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            print(f"[init OK] 本轮跑: {which}")
            for name in which:
                tool, args = TOOL_ARGS[name]
                print(f"\n{'='*60}\n>>> {tool}  {args}")
                try:
                    res = await s.call_tool(tool, args)
                    txt = res.content[0].text if res.content else "(空)"
                    print(f"<<< {tool} -> {len(txt)} 字")
                    print(txt[:900])
                except Exception as e:
                    print(f"<<< {tool} -> ❌ 异常: {type(e).__name__}: {str(e)[:300]}")
    print(f"\n[完成] {which}")

if __name__ == "__main__":
    asyncio.run(main())
