# 公开靶场普查（2026-09）— 在线免费靶场全死 / 被 WAF 挡

**结论**：2026-09 实测，没有一个「稳定在线 + 免费 + 能被 curl/浏览器直接驱动」的公开授权靶场。阳性对照一律走**离线 fixture 喂自研工具**（见 `tools/validate-positives.sh`），别再往"找活靶场"上磕时间。

## 逐个实测（本机 curl + 浏览器双验，全死因）

| 靶场 | 探活结果 | 死因 |
|---|---|---|
| owasp-juice.shop | 301 → juice-shop.github.io（REST API 全 404） | 免费实例下线，只剩 GitHub Pages 静态文档站，`/rest/*` 没了 |
| owasp-juice-shop.firebaseapp.com | 404（21k 静态站） | Firebase 免费壳早弃维护 |
| mutilld.sourceforge.net（4/3/1.11.4） | http 400（纯HTTP撞CF的HTTPS口）/ https 403 CF 挑战 | sourceforge 免费空间只托管静态文档，PHP 没跑；且 CF 拉黑数据中心 IP，浏览器也硬挡（"Sorry, you have been blocked"，Ray 明确拉黑） |
| test*.html5.vulnweb.com / dvwa.vulnweb.com | 400（同 CF 纯HTTP）/ 000 | vulnweb 老 DVWA 实例全死，域名挂 CF 拦 |
| portswigger.net web-security lab | 静态文档页 404（`/web-security/*` 子路径全改）；`/app-testing/lab-inventory` 是 301 但 lab host 是**每会话随机分配** `xxx.web-security-academy.net`，需登录 + JS 拿 | 拿不到固定可 curl 的授权端点；且 lab 要登录（Community 免费但需账号+JS） |
| bodge-it-2 / vulnerableapp / owasp-webgoat-demo (.herokuapp.com) | 404（herokuapp 免费空间 2025 起全关） | Heroku 免费 tier 砍了，这些 demo 全下线 |
| xss-game.appspot.com | 200 但 0B | GCP 免费 App Engine 早弃 |
| hackthebox.com | 302 | 要登录（不是无门槛靶场） |

## 正确做法（已落到工具）

1. **别找在线靶场**——2026 全被 CF/WAF/免费空间关停挡死，磕可达性是浪费时间。
2. **离线阳性对照**：`tools/validate-positives.sh` 喂本地 3 fixture（洞/转义/无回显）给 `xssprobe`，断 A/B/C 三态全对。零外网、零靶场（就几个 file:// 文件喂工具自测），证明"洞真存在时管线抓得住"。已接进 `test.sh` 第 ④ 段，回归全绿自动验。
3. **以后任何目标 0 命中**：先跑一次 `bash tools/validate-positives.sh` 确认工具健康（全 SKIP=chromium 不可用，此时**别**据此下"目标薄"结论；3/3 PASS=管线健康，0 命中可归因目标薄非工具瞎）。

## 判读提示（本普查顺带暴露的工具坑）
- `xssprobe` 判 B（转义）靠 `textContent.includes(canary)`：若页面**恰好含 canary 前缀串**会误判 B 而非 C。真实目标 canary 是 `HWXSS_<时间戳>` 唯一串，几乎不会撞；但离线 fixture 写"无 HWXSS"字样就会撞 → fixture 里别把 canary 前缀写进正文。
