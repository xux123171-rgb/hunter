# findings 模板（对齐 cybermes reports 结构，阶段4/5 出洞填这个）

> 放 `reports/<slug>/findings/<severity>_<vuln_name>.md`（snake_case，无方括号）。
> `findings/` 只放**已确认**的洞；信息性观察/缺头/版本泄露/阴性测试 → 归 `reports/<slug>/evidence/recon_notes.md`。
> 每个洞配一个可独立跑的 PoC：`reports/<slug>/pocs/poc_<vuln_name>.py`。
> 出完跑 `cybermes_aggregate_report`（或本地 aggregate）更新 SUMMARY.md/metadata.json。

## finding_<severity>_<name>.md 模板
```
# [严重性] 一句话标题（能到哪条链）
- 目标: <slug / URL>
- 端点: <method> <url>
- 前置: 未鉴权 / 需登录 / 需签名 / 需2账号
- 定级: <CVSS 向量>（按最远可达点，不按入口）
- primitive: <可控原语，一句话>
- 影响链: <primitive 最远推到哪>

## 证据（raw，可复现）
请求:
> <完整 curl，payload 克制>
响应关键段（diff 出差异的那部分，PII 首行打码）:
> <状态码 + 差异字段>
对照组: 合法值 → <正常响应>; payload → <异常响应>（有差异才成立）

## 7问核对
①可复现? ②真影响非报错? ③归属三截图齐? ④在范围内? ⑤没踩红线? ⑥定级对? ⑦对照组做了?
## FP-elimination（激进的排误报）
- 全路径防御点: <入口→sink 间每个校验/过滤/WAF>
- 结论: <每个防御点是否被 payload 过掉>
```

## PoC 骨架（poc_<name>.py，最小影响、自包含、非破坏）
```python
#!/usr/bin/env python3
# poc_<name>.py — <一句话>。最小影响，合规范围内，非破坏。
import sys, time, requests

TARGET = "<url>"
UA = {"User-Agent": "Mozilla/5.0"}

def run():
    # 1) 对照组：合法值
    legit = requests.get(TARGET, params={"id": "1"}, headers=UA, timeout=10)
    # 2) 攻击组：payload（克制：sleep 1 / 读 1 行 / 回显）
    t0 = time.time()
    pwn = requests.get(TARGET, params={"id": "1 AND SLEEP(1)"}, headers=UA, timeout=15)
    dt = time.time() - t0
    # 3) 判定：差异 = 实锤
    ok = (pwn.status_code == 200) and (len(pwn.text) != len(legit.text)) and (dt > 1.0)
    print("CONFIRMED" if ok else "REJECTED")
    print("delta_status", pwn.status_code, "delta_bytes", len(pwn.text)-len(legit.text), "delta_time", round(dt,2))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(run())
```

## 补天/盒子交付（阶段6，纯文本可复制）
三块框起来给用户直接粘贴：`简要描述` / `详细细节`(归属链+具体影响场景，不写空话) / `PoC`(克制 payload)。
截图逐张命名，本地上传勿粘贴。见 `templates/report-btt-vulbox.md`。
