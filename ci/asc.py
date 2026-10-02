#!/usr/bin/env python3
"""
App Store Connect API（GitHub Actions 的 TestFlight 流程用，.github/workflows/testflight.yml）。

  python3 ci/asc.py prepare
      確認 App ID（bundle id）註冊了，沒有就註冊；確認 App Store Connect 上有這個 App（沒有就停下來說明怎麼建）
  python3 ci/asc.py signing --dir <暫存資料夾> --name "StudioX CI 2610021405"
      這一次建置專用的簽章：打開 App ID 的推播能力、建一張 Apple Distribution 憑證（私鑰只在這台 Mac）、
      建 App Store 描述檔，寫出 signing.p12（密碼在 signing.pass）、profile.mobileprovision、appstore.entitlements，
      輸出 cert_id、profile_id、profile_uuid
  python3 ci/asc.py cleanup --cert <id> --profile <id>
      用完就撤銷憑證、刪掉描述檔（已經上傳的版本不受影響；不會越積越多）
  python3 ci/asc.py finish --app <id> --version 1.0 --build 2610021405 --notes notes.txt
      等 Apple 處理好這一版、寫「測試內容」、交給內部測試群組

金鑰從環境變數讀（GitHub 的 Secrets）：ASC_KEY_ID、ASC_ISSUER_ID、ASC_PRIVATE_KEY（.p8 的內容）。
只用標準函式庫＋PyJWT（pip install pyjwt cryptography）。
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "tw.studiox.console")
APP_NAME = os.environ.get("APP_NAME", "StudioX")


class ApiError(Exception):
    def __init__(self, status, method, path, detail):
        super().__init__(f"App Store Connect API {method} {path} → {status}: {detail[:1500]}")
        self.status = status


def token():
    key = os.environ["ASC_PRIVATE_KEY"].strip().replace("\\n", "\n")
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"},
    )


def call(method, path, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, method, path, e.read().decode(errors="replace")) from None


def summary(text):
    print(text)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text + "\n")


def output(key, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")


# ── prepare ──────────────────────────────────────────────────────────────────

def prepare():
    try:
        found = call("GET", "/bundleIds", query={"filter[identifier]": BUNDLE_ID, "limit": 200})
    except ApiError as e:
        if e.status in (401, 403):
            summary("### ❌ App Store Connect 不接受這把 API 金鑰\n"
                    "確認 GitHub Secrets 的 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY`（整個 .p8 的內容）沒貼錯，"
                    "而且金鑰的角色是 **Admin**（要能建憑證與描述檔）。")
            sys.exit(1)
        raise
    bundle = next((b for b in found.get("data", []) if b["attributes"]["identifier"] == BUNDLE_ID), None)
    if bundle is None:
        call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": BUNDLE_ID, "name": "StudioX Console", "platform": "IOS"}}})
        summary(f"- 註冊了 App ID `{BUNDLE_ID}`")
    else:
        summary(f"- App ID `{BUNDLE_ID}` 已註冊")

    apps = call("GET", "/apps", query={"filter[bundleId]": BUNDLE_ID, "limit": 1}).get("data", [])
    if not apps:
        summary(
            "### ⏸ App Store Connect 上還沒有這個 App\n"
            "Apple 不讓 API 建新的 App，這一步要在網頁上做一次（之後都自動）：\n"
            "1. 打開 https://appstoreconnect.apple.com/apps →「＋」→ 新增 App\n"
            f"2. 平台 iOS、名稱 {APP_NAME}、主要語言 繁體中文、套件 ID 選 `{BUNDLE_ID}`、SKU 填 `studiox-console`、使用者存取權 完整存取權\n"
            "3. 建好之後回 GitHub 的 Actions → TestFlight → Re-run jobs\n")
        sys.exit(1)
    app = apps[0]
    summary(f"- App Store Connect 上的 App：{app['attributes'].get('name')}（{app['id']}）")
    output("app_id", app["id"])


# ── signing ──────────────────────────────────────────────────────────────────

# App 用到的能力（StudioXConsole.entitlements）：App ID 要打開，描述檔裡才會有
CAPABILITIES = {
    "PUSH_NOTIFICATIONS": ("aps-environment", "production"),
    "USERNOTIFICATIONS_TIMESENSITIVE": ("com.apple.developer.usernotifications.time-sensitive", True),
}


def bundle_resource():
    found = call("GET", "/bundleIds", query={"filter[identifier]": BUNDLE_ID, "limit": 200}).get("data", [])
    bundle = next((b for b in found if b["attributes"]["identifier"] == BUNDLE_ID), None)
    if bundle is None:
        sys.exit(f"App ID {BUNDLE_ID} 還沒註冊（prepare 應該先註冊）")
    return bundle


def ensure_capabilities(bundle_id):
    """回傳打開了的能力。打不開的（例如 Apple 改了名稱）跳過，entitlements 也不放，不會讓整個建置失敗"""
    have = {c["attributes"].get("capabilityType") for c in
            call("GET", f"/bundleIds/{bundle_id}/bundleIdCapabilities", query={"limit": 200}).get("data", [])}
    enabled = []
    for cap in CAPABILITIES:
        if cap in have:
            enabled.append(cap)
            continue
        try:
            call("POST", "/bundleIdCapabilities", {"data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": cap},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}}}})
            enabled.append(cap)
            summary(f"- App ID 打開了 {cap}")
        except ApiError as e:
            if e.status == 409:
                enabled.append(cap)
            else:
                summary(f"- ⚠️ App ID 沒辦法打開 {cap}，這一版不含這項能力：{e}")
    return enabled


def write_entitlements(path, enabled):
    import plistlib
    ent = {CAPABILITIES[c][0]: CAPABILITIES[c][1] for c in enabled}
    with open(path, "wb") as f:
        plistlib.dump(ent, f)


def signing(args):
    import base64
    import secrets
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.x509.oid import NameOID

    os.makedirs(args.dir, exist_ok=True)
    bundle = bundle_resource()
    enabled = ensure_capabilities(bundle["id"])

    # 憑證：私鑰在這台 Mac 產生、只存在暫時的鑰匙圈，建置完就撤銷
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, args.name)]))
           .sign(key, hashes.SHA256()))
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    try:
        cert = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr_pem}}})["data"]
    except ApiError as e:
        if e.status == 409:
            summary("### ❌ Apple Distribution 憑證已經到上限\n"
                    "到 developer.apple.com → Certificates 撤銷用不到的 Distribution 憑證（名稱是「StudioX CI …」的可以直接撤銷），再重跑。")
            sys.exit(1)
        raise
    output("cert_id", cert["id"])
    der = base64.b64decode(cert["attributes"]["certificateContent"])
    certificate = x509.load_der_x509_certificate(der)

    # 舊版 macOS 的 security 只讀得懂傳統加密的 .p12
    password = secrets.token_urlsafe(24)
    encryption = (serialization.PrivateFormat.PKCS12.encryption_builder()
                  .kdf_rounds(50000)
                  .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
                  .hmac_hash(hashes.SHA1())
                  .build(password.encode()))
    with open(os.path.join(args.dir, "signing.p12"), "wb") as f:
        f.write(pkcs12.serialize_key_and_certificates(args.name.encode(), key, certificate, None, encryption))
    # 密碼只放在暫存資料夾（不進 GitHub 的輸出），也先遮掉
    print(f"::add-mask::{password}")
    with open(os.path.join(args.dir, "signing.pass"), "w") as f:
        f.write(password)

    # App Store 描述檔：只綁這張憑證
    profile = call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": args.name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
        }}})["data"]
    output("profile_id", profile["id"])
    output("profile_uuid", profile["attributes"]["uuid"])
    with open(os.path.join(args.dir, "profile.mobileprovision"), "wb") as f:
        f.write(base64.b64decode(profile["attributes"]["profileContent"]))

    write_entitlements(os.path.join(args.dir, "appstore.entitlements"), enabled)
    summary(f"- 這一次的簽章：憑證與描述檔「{args.name}」（建置完就撤銷）")


def cleanup(args):
    if args.profile:
        try:
            call("DELETE", f"/profiles/{args.profile}")
        except ApiError as e:
            summary(f"- ⚠️ 描述檔沒有刪掉：{e}")
    if args.cert:
        try:
            call("DELETE", f"/certificates/{args.cert}")
            summary("- 撤銷了這一次的憑證、刪掉描述檔（已經上傳的版本不受影響）")
        except ApiError as e:
            summary(f"- ⚠️ 憑證沒有撤銷，到 developer.apple.com 撤銷名稱是「StudioX CI …」的那張：{e}")


# ── finish ───────────────────────────────────────────────────────────────────


def wait_for_build(app_id, version, build, minutes=40):
    deadline = time.time() + minutes * 60
    while time.time() < deadline:
        builds = call("GET", "/builds", query={
            "filter[app]": app_id, "filter[version]": build,
            "filter[preReleaseVersion.version]": version, "limit": 1,
        }).get("data", [])
        if builds:
            state = builds[0]["attributes"].get("processingState")
            if state == "VALID":
                return builds[0]
            if state in ("FAILED", "INVALID"):
                summary(f"### ❌ Apple 處理這一版失敗（{state}）\n到 App Store Connect → TestFlight 看原因（通常也會寄信）。")
                sys.exit(1)
        time.sleep(30)
    summary(f"### ⏳ Apple 還在處理 {version}（{build}），超過 {minutes} 分鐘\n處理好之後一樣會出現在 TestFlight，只是這次沒寫到「測試內容」。")
    sys.exit(0)


def whats_new(app_id, build_id, text):
    locs = call("GET", f"/builds/{build_id}/betaBuildLocalizations").get("data", [])
    if locs:
        for loc in locs:
            call("PATCH", f"/betaBuildLocalizations/{loc['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}})
    else:
        locale = call("GET", f"/apps/{app_id}").get("data", {}).get("attributes", {}).get("primaryLocale") or "zh-Hant"
        call("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": locale, "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    summary("- 寫好了 TestFlight 的「測試內容」")


def give_to_internal_groups(app_id, build_id):
    groups = call("GET", f"/apps/{app_id}/betaGroups", query={"limit": 50}).get("data", [])
    internal = [g for g in groups if g["attributes"].get("isInternalGroup")]
    if not internal:
        summary("- ⚠️ 還沒有內部測試群組：App Store Connect → TestFlight → 內部測試「＋」建一個、把自己加進去，之後每一版都會自動出現")
        return
    for g in internal:
        name = g["attributes"].get("name")
        if g["attributes"].get("hasAccessToAllBuilds"):
            summary(f"- 內部群組「{name}」自動拿到所有版本")
            continue
        try:
            call("POST", f"/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": build_id}]})
            summary(f"- 交給內部群組「{name}」")
        except ApiError as e:
            summary(f"- ⚠️ 沒有交給「{name}」：{e}")


def finish(args):
    build = wait_for_build(args.app, args.version, args.build)
    summary(f"### ✅ {args.version}（{args.build}）已經在 TestFlight")
    text = open(args.notes, encoding="utf-8").read().strip()[:3900] if args.notes else ""
    if text:
        try:
            whats_new(args.app, build["id"], text)
        except ApiError as e:
            summary(f"- ⚠️ 「測試內容」沒有寫上去：{e}")
    give_to_internal_groups(args.app, build["id"])


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("prepare")
    sg = sub.add_parser("signing")
    sg.add_argument("--dir", required=True)
    sg.add_argument("--name", required=True)
    c = sub.add_parser("cleanup")
    c.add_argument("--cert", default="")
    c.add_argument("--profile", default="")
    f = sub.add_parser("finish")
    f.add_argument("--app", required=True)
    f.add_argument("--version", required=True)
    f.add_argument("--build", required=True)
    f.add_argument("--notes")
    args = p.parse_args()
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(name, "").strip():
            sys.exit(f"缺少 {name}")
    {"prepare": lambda: prepare(), "signing": lambda: signing(args),
     "cleanup": lambda: cleanup(args), "finish": lambda: finish(args)}[args.cmd]()


if __name__ == "__main__":
    main()
