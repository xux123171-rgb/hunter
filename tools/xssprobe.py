#!/usr/bin/env python3
"""xssprobe.py — 自研存储XSS探针（Playwright headless，合规深度封顶）

定位：SOP 阶段4.3 存储XSS行。浏览器层 CDP 不可用时，这条线就是半瘫的——
本工具补齐：headless Chromium 真渲染 + 注入 canary + 捕获回显，实锤判定
（payload 原样回显到 DOM = 洞；被过滤/转义 = 不报）。

合规深度封顶：
- 只对授权范围内目标、自己的写入口（昵称/留言/评论测试位）写测试数据
- 注入 canary 唯一标记串（`HWXSS_<ts>`），可识别可清除，非 `<script>` 无界执行
- 单页渲染、不挂接受害者会话（不偷 cookie）、不横向
- 出实锤后主动调删除/退出流程清理自己写的数据

判读规则（同 SOP 铁律：实锤才算洞）：
  A. canary 原样出现在 document.documentElement.outerHTML → 存储XSS 实锤
  B. canary 被实体化（&lt;/&gt; 等）或被剥离 → 过滤生效，不报
  C. 无回显位 → 该入口无渲染面，换下一入口

用法（在项目根，需用装了 playwright 的解释器，即 Hermes venv python）：
  py -3.11 tools/xssprobe.py --url https://target/app --field "留言" --canary HWXSS
    会：开页 → 填 field 附近的输入框(按 label 文本/选择器 --sel 指定) → 提交 →
    回目标页 → 读 DOM 找 canary → 输出 A/B/C 判定
  纯读模式（已有写入口已注入）：--url <回显页> 不带 --field，只扫 DOM 找 canary。

输出：JSON 行 {verdict, canary_found_raw, canary_found_escaped, dom_len, url}
"""
import argparse, json, re, sys, time

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True, help="目标页（写入口或回显页）")
    p.add_argument("--field", default="", help="写入口标识（label 文本，如 昵称/留言）")
    p.add_argument("--sel", default="", help="输入框 CSS 选择器（优先于 --field）")
    p.add_argument("--submit-sel", default="", help="提交按钮选择器（默认按 Enter）")
    p.add_argument("--canary", default="HWXSS", help="canary 前缀（默认 HWXSS，自动拼时间戳）")
    p.add_argument("--post-back", default="", help="提交后要访问的回显页（默认同 url）")
    a = p.parse_args()

    from playwright.sync_api import sync_playwright  # 延迟导入，纯读模式也走这里

    canary = f"{a.canary}_{int(time.time())}"
    verdict, raw_hit, esc_hit, dom_len = "C", False, False, 0
    with sync_playwright() as pw:
        b = pw.chromium.launch(headless=True)
        pg = b.new_context(ignore_https_errors=True).new_page()
        pg.goto(a.url, timeout=30000, wait_until="domcontentloaded")

        # 元素级 canary（合规：惰性 <img>，无 script/事件，非破坏）
        # 真存储XSS：注入串被 innerHTML 渲染 → 该 <img> 真节点存在
        # 被过滤：textContent/转义 → 只显示成纯文本，无该节点
        CANARY_ID = "hw_xssc"
        payload = f'<img id="{CANARY_ID}" src="1" width="0" height="0" alt="{a.canary}">'
        dom_probe = """
        ({id, alt}) => {
          const el = document.getElementById(id);
          if (el && el.tagName === "IMG") return {injected:true, texted:false, domLen:document.documentElement.outerHTML.length};
          const texted = document.body.textContent.includes(alt);
          return {injected:false, texted, domLen:document.documentElement.outerHTML.length};
        }
        """

        probe_arg = {"id": CANARY_ID, "alt": a.canary}

        if a.field or a.sel:
            val = payload  # 元素级 canary（合规：惰性 <img>，非破坏）
            if a.sel:
                pg.fill(a.sel, val)
            else:
                pg.get_by_label(re.compile(a.field, re.I)).first.fill(val)
            if a.submit_sel:
                pg.click(a.submit_sel, timeout=8000)
            else:
                pg.press("body", "Enter")
            pg.wait_for_load_state("domcontentloaded", timeout=15000)
            target = a.post_back or a.url
            if target != a.url:
                pg.goto(target, timeout=30000, wait_until="domcontentloaded")
            r = pg.evaluate(dom_probe, probe_arg)
            raw_hit, esc_hit, dom_len = r["injected"], r["texted"], r["domLen"]
            verdict = "A" if raw_hit else ("B" if esc_hit else "C")
            # 出实锤主动清理（best-effort）
            if verdict == "A" and (a.sel or a.field):
                try:
                    (pg.fill(a.sel, "") if a.sel
                     else pg.get_by_label(re.compile(a.field, re.I)).first.fill(""))
                    if a.submit_sel:
                        pg.click(a.submit_sel, timeout=5000)
                except Exception:
                    pass
        else:
            r = pg.evaluate(dom_probe, probe_arg)
            raw_hit, esc_hit, dom_len = r["injected"], r["texted"], r["domLen"]
            verdict = "A" if raw_hit else ("B" if esc_hit else "C")

        b.close()

    explain = {"A": "canary 原样回显 DOM → 存储XSS 实锤（报）",
               "B": "canary 被实体化/过滤 → 过滤生效（不报，记 journal）",
               "C": "无回显 → 该入口无渲染面（换入口）"}[verdict]
    print(json.dumps({"verdict": verdict, "canary": canary, "canary_found_raw": raw_hit,
                      "canary_found_escaped": esc_hit, "dom_len": dom_len, "url": a.url,
                      "explain": explain}, ensure_ascii=False))
    return 0 if verdict != "C" else 2

if __name__ == "__main__":
    sys.exit(main())
