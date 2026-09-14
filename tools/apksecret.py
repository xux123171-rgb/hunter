#!/usr/bin/env python3
"""apksecret.py — apk 反编译前置腿（纯 stdlib，零 Java 依赖）

定位：SOP A'移动端线第①②步的自动化部分。apk 本质是 zip：
解包扫 assets/res/raw/js 里的 硬编码密钥/API基址/内网域名/凭证 —— 这一步
不需要 jadx（Java）；dex 反编到方法级才需要，留给手工环节（文档写明）。

合规：只扫文件内容特征，不重签名不篡改；扫的是授权目标自家发布的 apk。

用法:
  python tools/apksecret.py scan <apk路径|解包目录> [--json]
  python tools/apksecret.py scan app.apk

输出：
  URLS     — http(s) 端点去重（API 基址/内网域名候选，喂 A1 子域扩面 & L5 源站）
  SECRETS  — AK/SK、token、password、jwt、第三方 appid/secret 模式命中
  MANIFEST — 包名/版本/权限（定位组件暴露面参考）
"""
import io, json, os, re, sys, zipfile

PATTERNS = {
    "ak_aliyun":   re.compile(r"LTAI[A-Za-z0-9]{12,22}"),
    "ak_tencent":  re.compile(r"AKID[A-Za-z0-9]{13,20}"),
    "ak_aws":      re.compile(r"AKIA[0-9A-Z]{16}"),
    "jwt":         re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{8,}"),
    "password":    re.compile(r"(?:pass(?:word)?|pwd|secret|token|apikey|api_key|access_key|client_secret)[\"'\s:=]{1,6}([^\s\"'&,;<]{8,64})", re.I),
    "private_key": re.compile(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----"),
    "url":         re.compile(r"https?://[a-zA-Z0-9][a-zA-Z0-9.\-_:]{3,80}/?[a-zA-Z0-9./_\-?=&%]{0,60}"),
}
SKIP_EXT = (".png",".jpg",".jpeg",".gif",".webp",".mp3",".mp4",".ogg",".wav",".so",".dex",".arsc",".ttf",".otf",".ico")
MAXSIZE = 8 * 1024 * 1024  # 单文件 >8MB 跳过（资源/库不是文本扫描对象）

def scan_bytes(data, name, urls, secrets, manifest):
    if name.endswith("AndroidManifest.xml") and b"package=" in data:
        m = re.findall(rb'(?:package|android:versionName)="?([\w.]+)"?', data[:4000])
        manifest.setdefault("hint", []).extend(x.decode(errors="replace") for x in m[:4])
    # 只对可打印比率高的文本扫
    printable = sum(32 <= b < 127 or b in (9,10,13) for b in data[:4000])
    if printable / max(1, len(data[:4000])) < 0.8:
        return
    text = data.decode("utf-8", "replace")
    for kind, pat in PATTERNS.items():
        for m in pat.finditer(text):
            val = m.group(1) if (m.groups() and m.group(1)) else m.group(0)
            if kind == "url":
                urls.add(val.split("?")[0])
            else:
                secrets.append((kind, name, val[:80]))

def main():
    if len(sys.argv) < 3 or sys.argv[1] != "scan":
        print(__doc__); sys.exit(1)
    src = sys.argv[2]
    urls, secrets, manifest = set(), [], {}
    if os.path.isdir(src):  # 已解包目录
        for root, _, files in os.walk(src):
            for fn in files:
                if fn.lower().endswith(SKIP_EXT): continue
                fp = os.path.join(root, fn)
                try:
                    if os.path.getsize(fp) > MAXSIZE: continue
                    with open(fp, "rb") as f:
                        scan_bytes(f.read(), fp.replace(root, ""), urls, secrets, manifest)
                except OSError:
                    pass
    else:  # zip/apk 直接扫
        with zipfile.ZipFile(src) as z:
            for info in z.infolist():
                if info.filename.lower().endswith(SKIP_EXT) or info.file_size > MAXSIZE: continue
                try:
                    scan_bytes(z.read(info), info.filename, urls, secrets, manifest)
                except Exception:
                    pass
    out = {"source": src, "manifest": manifest, "urls": sorted(urls), "secrets": secrets[:80]}
    if "--json" in sys.argv:
        print(json.dumps(out, ensure_ascii=False, indent=1))
    else:
        print(f"== {src} ==")
        print(f"URL/端点 {len(out['urls'])} 个：")
        for u in out["urls"][:40]: print("  ", u)
        print(f"密钥候选 {len(out['secrets'])} 条：")
        for k, f_, v in out["secrets"][:25]: print(f"   [{k}] {f_}: {v}")
        print("→ 后续手工：需要方法级逻辑用 jadx 反编（装 Java 后）；dex 不在本腿范围")
    return 0

if __name__ == "__main__":
    sys.exit(main())
