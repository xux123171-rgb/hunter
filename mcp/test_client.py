"""干净验证 hunter MCP：用官方 mcp client 走 stdio 握手+列工具+调安全工具。"""
import asyncio, os
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = r"C:\Users\ThinkPad\Documents\src-xiaoxu\hunter"
PY = ROOT + r"\mcp\.venv\Scripts\python.exe"
SRV = ROOT + r"\mcp\server.py"

async def main():
    params = StdioServerParameters(command=PY, args=[SRV])
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            init = await s.initialize()
            print("initialize -> OK", init.serverInfo)
            tools = await s.list_tools()
            print(f"tools/list -> {len(tools.tools)} 个:")
            for t in tools.tools:
                print(f"   - {t.name}: {(t.description or '').splitlines()[0][:70]}")
            def txt(res):
                return res.content[0].text if res.content else "(空)"
            b = await s.call_tool("hunter_brain", {"what": "waf"})
            print(f"\nhunter_brain(waf) -> {len(txt(b))} 字  首行: {txt(b).splitlines()[0][:60] if txt(b) else '(空)'}")
            d = await s.call_tool("hunter_accounts", {"cmd": "domains"})
            print(f"hunter_accounts(domains) -> {txt(d).strip()[:80]}")
            p = await s.call_tool("hunter_probe", {"url": "https://example.com/"})
            print(f"hunter_probe(example.com) -> {len(txt(p))} 字  含指纹: {'CODE' in txt(p)}")

asyncio.run(main())
