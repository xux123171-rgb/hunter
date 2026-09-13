#!/usr/bin/env python3
"""mailacct.py — 合规双邮箱账号 + 自动提验证码（我们的自有账号获取通道，破越权天花板）

基于 mail.tm（纯 REST，自建可收发的临时邮箱）。IDOR/越权要 2 个登录态账号，
本工具一键建 2 个独立邮箱 + 抓它们的收件箱 + 提取 4~6 位验证码，供打洞时
注册/验证/密码重置走邮箱流程用。手机号/SMS 不在本工具范围（单独处理）。

设计原则（跟整套 SOP 一致）：工具只给"原材料"（最新邮件正文），最终判读由操盘手做，
不硬编码死板提取规则（各目标验证码邮件格式不同）。

用法：
  python tools/mailacct.py domains                     # 看 mail.tm 当前可用域名
  python tools/mailacct.py create --tag hunter         # 建 2 个独立账号，存 scratch/<tag>.mailacct.json
  python tools/mailacct.py inbox  --tag hunter         # 读两号收件箱（最新 5 封主题）
  python tools/mailacct.py otp    --tag hunter          # 提两号里的 4~6 位验证码 + 验证链接（参考，我判读）
  python tools/mailacct.py test   --tag hunter         # A 给 B 发自测信（带 6 位码），验证收发闭环

state 存 scratch/<tag>.mailacct.json（gitignored 工作区），含 两号 address+token。
"""
import argparse, json, os, re, ssl, sys, time, urllib.request, urllib.error

API = "https://api.mail.tm"
CTX = ssl.create_default_context()

def _call(path, token=None, method="GET", data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(API + path, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=25, context=CTX) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return {"_err": f"HTTP {e.code}: {e.read().decode()[:200]}"}
    except Exception as e:
        return {"_err": str(e)}

def domains():
    d = _call("/domains")
    out = [x["domain"] for x in d.get("hydra:member", []) if x.get("isActive")]
    return out or [x["domain"] for x in d.get("hydra:member", [])] or ["uberip.com"]

def state_path(tag):
    base = os.path.join(os.path.dirname(__file__), os.pardir, "scratch")
    os.makedirs(base, exist_ok=True)
    return os.path.join(base, f"{tag}.mailacct.json")

def create(tag, n=2):
    dom = domains()[0]
    tagbase = re.sub(r"\W", "", tag) or "hw"
    # mail.tm 建号**无需** guest token，无鉴权直接 POST /accounts（实测 201）
    made = []
    for i in range(n):
        addr = f"hw{tagbase}{i}{int(time.time())%100000}@{dom}"
        c = _call("/accounts", method="POST",
                  data={"address": addr, "password": "Hunter!2026"})
        ok = c.get("_err") is None and c.get("id")
        # 地址偶发已存在 → 换尾号重试一次
        if not ok:
            addr = f"hw{tagbase}{i}{int(time.time())%1000000}@{dom}"
            c = _call("/accounts", method="POST",
                      data={"address": addr, "password": "Hunter!2026"})
            ok = c.get("_err") is None and c.get("id")
        lk = _call("/token", method="POST",
                   data={"address": c.get("address", addr), "password": "Hunter!2026"})
        made.append({"address": c.get("address", addr), "created": ok,
                     "token": lk.get("token", "")})
    sp = state_path(tag)
    json.dump({"domain": dom, "created_at": time.time(), "accounts": made},
              open(sp, "w"), ensure_ascii=False, indent=2)
    print(f"已建 {len(made)} 个邮箱账号 → {sp}")
    for a in made:
        print(f"  #{'A' if a is made[0] else 'B'} {a['address']}  created={a['created']}  token={'ok' if a['token'] else 'MISSING'}")
    return 0

def load(tag):
    sp = state_path(tag)
    if not os.path.exists(sp):
        print("无 state，先 run create --tag", tag); sys.exit(1)
    return json.load(open(sp))

def _messages(a):
    lst = _call("/messages", token=a["token"])
    return lst.get("hydra:member", []) if lst.get("_err") is None else []

def inbox(tag, n=5):
    st = load(tag)
    for i, a in enumerate(st["accounts"]):
        label = "A" if i == 0 else "B"
        msgs = _messages(a)[:n]
        print(f"--- 账号{label} {a['address']} （{len(msgs)} 封）---")
        for m in msgs:
            frm = (m.get("from") or {}).get("address", "?")
            print(f"   {m.get('subject','(无主题)')!r}  from={frm}  id={m.get('id')}")
    return 0

OTP6 = re.compile(r"\b\d{6}\b")
OTP4 = re.compile(r"\b\d{4}\b")
LINK = re.compile(r"https?://[^\s\"'<>]+")

def otp(tag):
    st = load(tag)
    found_any = False
    for i, a in enumerate(st["accounts"]):
        label = "A" if i == 0 else "B"
        for m in _messages(a):
            mid = m.get("id")
            detail = _call(f"/messages/{mid}", token=a["token"])
            text = " ".join([detail.get("text", ""), (detail.get("html") or "")])
            c6 = OTP6.findall(text); c4 = OTP4.findall(text) if not c6 else []
            links = LINK.findall(text)[:3]
            code = (c6 or c4)
            if code or links:
                found_any = True
                print(f"账号{label} {a['address']} | 主题={m.get('subject','')!r}")
                if code:
                    print(f"   验证码候选(优先6位): {code[:5]}")
                if links:
                    print(f"   验证链接: {links}")
    if not found_any:
        print("（两号收件箱暂无验证码/链接——目标尚未发信或格式特殊，请 inbox 看原始正文）")
    return 0

def test(tag):
    st = load(tag)
    a, b = st["accounts"][0], st["accounts"][1]
    code = "847291"
    r = _call("/messages", token=a["token"], method="POST",
              data={"to": [b["address"]], "subject": "Test verification code",
                    "text": f"Your verification code is {code}. It expires in 10 min."})
    send_ok = r.get("_err") is None
    print(f"A→B 发信: {'ok' if send_ok else '发信端点不可用（mail.tm 未开放此匿名发信接口，405）'}")
    if not send_ok:
        print("说明：打洞真正用的是【收件侧】inbox/otp（收目标站发来的验证码），发信仅作闭环自测，不影响挖洞能力。")
    print("轮询 B 收件箱提码（最多 8 次×2s）...")
    got = None
    for _ in range(8):
        time.sleep(2)
        for m in _messages(b):
            d = _call(f"/messages/{m.get('id')}", token=b["token"])
            t = " ".join([d.get("text", ""), (d.get("html") or "")])
            if code in t:
                got = code; break
        if got:
            break
    print(f"闭环: B 收到并提取到验证码 = {got}  {'✅ 收发+提码 OK' if got else '❌ 未收到(检查发信 err 或 mail.tm 投递)'}")
    return 0

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["domains", "create", "inbox", "otp", "test"])
    p.add_argument("--tag", default="hunter")
    args = p.parse_args()
    fn = {"domains": lambda: print(domains()), "create": lambda: create(args.tag),
          "inbox": lambda: inbox(args.tag), "otp": lambda: otp(args.tag),
          "test": lambda: test(args.tag)}[args.cmd]
    sys.exit(fn() or 0)
