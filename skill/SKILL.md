---
name: hunter
description: "Use when hunting web vulns on an authorized target domain. 调 hunter_brain(playbook) 拿全套作战 SOP/铁律/判死速查，再按 SOP 用 8 条腿（recon/probe/crawl/scan/fuzz/xss/accounts）执行——只报有 PoC 的实锤。"
version: 1.0.0
platforms: [windows, linux, macos]
metadata:
  hermes:
    tags: [vulnerability, bug-bounty, web-security, authorized-testing]
---

# hunter — 全谱系挖洞流程（触发器）

**这是薄触发器。真正的脑子在 `hunter` MCP 服务端**（`hunter_brain` 工具按需取，随仓库 clone 走，永不失同步）。
本 skill 只做两件事：**① 让 Hermes 打洞时先读脑子再动手；② 立合规纪律。**

## 何时触发
用户要挖某域名/站点的洞、补天/漏洞盒子提交前做全量侦察、或说「打 xxx.com」时加载。

## 执行纪律（铁律，先于一切动作）
1. **先读脑子**：第一步必须 `hunter_brain(what="playbook")` 取完整作战手册，再决定打哪条腿。
   - 影响/优先级门 → `hunter_brain("gates")`
   - 遇到 WAF 要绕过 → `hunter_brain("waf")`
   - 业务逻辑/并发洞 → `hunter_brain("race")`
2. **合规深度封顶**：SQLi/RCE/XSS/越权/race 一律停在最小证明（1 行 / 1 条命令 / 1 个 canary / 1 个 ID），
   不下全量、不拖库、不爆破、不横向。payload 克制（sleep 1、回显、canary）。
3. **实锤才算洞**：接口返回 success 不算；必须证明真实影响（数据真泄露/真越权/真读文件）。
   无法验证影响（被 CDN 掩盖、等审核拿不到 token）的直接判死不磕。
4. **零落地探活**：只看响应头/状态码/字节数判 WAF/CMS，不下全量 JS/JSON。

## 8 条腿（对应 MCP 工具，全在项目内）
| 腿 | 工具 | 阶段 |
|----|------|------|
| 子域+官网源码 | `hunter_recon` | 1+2 |
| 官网栏目探活 | `hunter_probe` | 2 |
| 面绘制(端点+JS) | `hunter_crawl` | 3 |
| 非破坏模板扫 | `hunter_scan` | 4 |
| 目录/端点 fuzz | `hunter_fuzz` | 4 |
| 存储XSS三态 | `hunter_xss` | 4 |
| 越权双账号 | `hunter_accounts` | 越权线 |
| 取脑子 | `hunter_brain` | 全程 |

## 归属证明（报洞必做）
官网 logo + 页脚备案 + 跳转过程，三张截图。影响写具体利用场景，不写空话。

> 换机器重装：clone 仓库后跑 `bash tools/install-hermes.sh`（引擎+模板+venv+本 skill+MCP 一条命令，缺啥补啥）。
