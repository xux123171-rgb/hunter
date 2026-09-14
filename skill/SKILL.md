---
name: hunter
description: "Use when hunting web vulns on an authorized target domain. 调 hunter_brain(playbook) 拿全套作战 SOP/铁律/判死梯子，再按 SOP 用 11 条腿（recon/probe/crawl/scan/fuzz/matrix/monitor/xss/accounts/apk）执行——只报有 PoC 的实锤。"
version: 1.1.0
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
   - 遇到 WAF 要绕过 → `hunter_brain("waf")`（含 401/403 绕过字典 §0.5）
   - 判死前强制爬梯 → `hunter_brain("ladder")`（L0-L7，"被WAF拦"≠证据穷尽）
   - 业务逻辑/并发洞 → `hunter_brain("race")`（race 必须 barrier 齐射）
2. **合规深度封顶**：SQLi/RCE/XSS/越权/race 一律停在最小证明（1 行 / 1 条命令 / 1 个 canary / 1 个 ID），
   不下全量、不拖库、不爆破、不横向。payload 克制（sleep 1、回显、canary）。
3. **实锤才算洞**：接口返回 success 不算；必须证明真实影响（数据真泄露/真越权/真读文件）。
   无法验证影响（被 CDN 掩盖、等审核拿不到 token）的直接判死不磕。
4. **零落地探活**：只看响应头/状态码/字节数判 WAF/CMS，不下全量 JS/JSON。
5. **矩阵状态机**：阶段4 开工先建 `scratch/<slug>/matrix.md`（可打面 A1-A9 × 活资产），每格只允许终态=实锤/已试(记请求数)/判死(写证据)；一项不通立刻接下一项不磕；判死前必须跑完最低三件套(nuclei模板扫+ffuf关键路径+katana爬)或写明可复核的豁免证据；矩阵清空前无权宣布"打完"。
6. **回显三查**：任何有回显的参数，判死前独立测完 ①注入 ②XSS canary 活体 ③跳转参数——SQLi 无 diff ≠ 回显安全。
7. **腿损坏降级**：MCP 腿卡死/重启失败/返回乱码时，用 `tools/hunter-cli.sh` 的手动等价命令照跑三件套（对照表见 `hunter_brain("playbook")` 的「MCP 腿损坏时的降级执行路径」），**不阻塞判死流程**；存储 XSS 面主动调 `tools/xssprobe.py`（Playwright 元素级三态实锤），别全程 curl 文本级低配判。降级≠豁免，三件套手动跑完才算达成最低深度门槛。

## 11 条腿（对应 MCP 工具，全在项目内）
| 腿 | 工具 | 阶段 |
|----|------|------|
| 子域+官网源码 | `hunter_recon` | 1+2 |
| 官网栏目探活 | `hunter_probe` | 2 |
| 面绘制(端点+JS) | `hunter_crawl` | 3 |
| 非破坏模板扫 | `hunter_scan` | 4 |
| 目录/端点 fuzz | `hunter_fuzz` | 4 |
| 攻击面矩阵 | `hunter_matrix` | 4 开工必建 |
| 资产快照diff | `hunter_monitor` | 持续侦察 |
| 存储XSS三态 | `hunter_xss`（--then 多步流） | 4 |
| 越权双账号 | `hunter_accounts` | 越权线 |
| apk密钥扫描 | `hunter_apk` | A' 移动端 |
| 取脑子 | `hunter_brain` | 全程 |

## 归属证明（报洞必做）
官网 logo + 页脚备案 + 跳转过程，三张截图。影响写具体利用场景，不写空话。

> 换机器重装：clone 仓库后跑 `bash tools/install-hermes.sh`（引擎+模板+venv+本 skill+MCP 一条命令，缺啥补啥）。
