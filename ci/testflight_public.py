#!/usr/bin/env python3
"""
TestFlight 公開測試（外部測試員）：給一個連結，任何人用 iPhone 點開就能裝測試版，不用是 App Store Connect 的團隊成員。

  python3 ci/testflight_public.py --version 1.1                最新一個處理好的 build
  python3 ci/testflight_public.py --version 1.1 --build 2610040300 --wait 45

做的事（做過的不重做，可以一直重跑）：
  1. 測試版的 App 資訊：描述、隱私權政策、行銷網址（ci/appstore/metadata.json），意見回饋 Email
  2. 測試版審核資訊：聯絡人（照 App Store 審核聯絡人，網頁上填的）、審核說明（示範模式怎麼進去）
  3. 外部測試群組「公開測試」：沒有就建一個，打開公開連結（最多 PUBLIC_LINK_LIMIT 人，預設 100）
  4. 把 build 交給這個群組、送 Apple 的測試版審核（每個版本號的第一個 build 要審，通常一天內；之後的 build 多半直接過）
  5. --wait：等審核結果（分鐘），過了就把公開連結寫在摘要

Email、電話只在執行時從 App Store Connect 讀，不寫進 repo、不印出來。
公開連結誰拿到都能裝（App 要 StudioX 帳號才看得到真的資料，沒有帳號只能看示範），
不想再收人時到 App Store Connect → TestFlight →「公開測試」關掉公開連結或調低人數上限。
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from asc import ApiError, BUNDLE_ID, apple_error, call, mask, output, summary  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GROUP = os.environ.get("PUBLIC_GROUP", "公開測試")
LIMIT = int(os.environ.get("PUBLIC_LINK_LIMIT", "100"))

STATES = {
    "PROCESSING": "Apple 還在處理這個 build",
    "PROCESSING_EXCEPTION": "Apple 處理這個 build 失敗",
    "MISSING_EXPORT_COMPLIANCE": "缺出口合規（加密）的回答",
    "READY_FOR_BETA_SUBMISSION": "還沒送測試版審核",
    "IN_EXPORT_COMPLIANCE_REVIEW": "出口合規審查中",
    "WAITING_FOR_BETA_REVIEW": "等 Apple 的測試版審核（第一次通常一天內）",
    "IN_BETA_REVIEW": "Apple 正在審核",
    "BETA_REJECTED": "測試版審核沒過",
    "BETA_APPROVED": "測試版審核通過",
    "READY_FOR_BETA_TESTING": "可以測了",
    "IN_BETA_TESTING": "測試中",
    "EXPIRED": "這個 build 過期了（TestFlight 的 build 放 90 天）",
}
OPEN = {"BETA_APPROVED", "READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}
PENDING = {"WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "IN_EXPORT_COMPLIANCE_REVIEW", "PROCESSING"}


def meta():
    with open(os.path.join(HERE, "appstore", "metadata.json"), encoding="utf-8") as f:
        return json.load(f)


def app():
    apps = call("GET", "/apps", query={"filter[bundleId]": BUNDLE_ID, "limit": 1}).get("data", [])
    if not apps:
        summary("### ❌ App Store Connect 上沒有這個 App（先跑一次 TestFlight 的流程）")
        sys.exit(1)
    return apps[0]


def store_contact(app_id):
    """App Store 審核聯絡人（網頁上填的）：測試版審核的聯絡人、意見回饋 Email 用同一位"""
    versions = call("GET", f"/apps/{app_id}/appStoreVersions", query={"filter[platform]": "IOS", "limit": 10}).get("data", [])
    for v in versions:
        try:
            d = call("GET", f"/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data")
        except ApiError:
            continue
        a = (d or {}).get("attributes") or {}
        if a.get("contactEmail"):
            return a
    return {}


# ── 測試版的 App 資訊、審核資訊 ───────────────────────────────────────────────

def beta_app_info(a, m, contact):
    app_id = a["id"]
    locale = a["attributes"].get("primaryLocale") or m["locale"]
    locs = call("GET", f"/apps/{app_id}/betaAppLocalizations").get("data", [])
    loc = next((x for x in locs if x["attributes"].get("locale") == locale), locs[0] if locs else None)
    attrs = {
        "description": m["description"][:4000],
        "privacyPolicyUrl": m["privacyPolicyUrl"],
        "marketingUrl": m["marketingUrl"],
    }
    feedback = (loc or {}).get("attributes", {}).get("feedbackEmail") if loc else None
    if not feedback and contact.get("contactEmail"):
        attrs["feedbackEmail"] = contact["contactEmail"]
        feedback = contact["contactEmail"]
    if loc:
        call("PATCH", f"/betaAppLocalizations/{loc['id']}", {"data": {
            "type": "betaAppLocalizations", "id": loc["id"], "attributes": attrs}})
    else:
        call("POST", "/betaAppLocalizations", {"data": {
            "type": "betaAppLocalizations", "attributes": {"locale": locale, **attrs},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    if feedback:
        summary(f"- 測試版的 App 資訊（描述、隱私權政策）；意見回饋 Email {mask(feedback)}（測試員看得到，"
                "要換到 App Store Connect → TestFlight → 測試資訊）")
    else:
        summary("- ⚠️ 還沒有意見回饋 Email：App Store Connect → TestFlight → 測試資訊 →「意見回饋電子郵件」填一個")
    return bool(feedback)


def beta_review_info(app_id, m, contact):
    attrs = {"notes": m["reviewNotes"][:4000], "demoAccountRequired": False}
    detail = call("GET", f"/apps/{app_id}/betaAppReviewDetail").get("data") or {}
    have = detail.get("attributes") or {}
    for key in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
        if not have.get(key) and contact.get(key):
            attrs[key] = contact[key]
    call("PATCH", f"/betaAppReviewDetails/{detail['id']}", {"data": {
        "type": "betaAppReviewDetails", "id": detail["id"], "attributes": attrs}})
    missing = [label for key, label in (("contactFirstName", "名"), ("contactLastName", "姓"), ("contactPhone", "電話"),
                                         ("contactEmail", "Email")) if not (have.get(key) or attrs.get(key))]
    if missing:
        summary(f"- ⚠️ 測試版審核的聯絡人還缺：{'、'.join(missing)}（App Store Connect → TestFlight → 測試資訊 → 審核資訊）")
    else:
        summary("- 測試版審核資訊：聯絡人（照 App Store 審核聯絡人）、審核說明（示範模式）")
    return not missing


# ── 外部測試群組與公開連結 ────────────────────────────────────────────────────

def public_group(app_id):
    groups = call("GET", f"/apps/{app_id}/betaGroups").get("data", [])
    external = [g for g in groups if not g["attributes"].get("isInternalGroup")]
    g = next((x for x in external if x["attributes"].get("name") == GROUP), None) \
        or next((x for x in external if x["attributes"].get("publicLinkEnabled")), None)
    if g:
        return g
    base = {"name": GROUP, "isInternalGroup": False, "feedbackEnabled": True}
    link = {"publicLinkEnabled": True, "publicLinkLimitEnabled": True, "publicLinkLimit": LIMIT}
    rel = {"app": {"data": {"type": "apps", "id": app_id}}}
    try:
        g = call("POST", "/betaGroups", {"data": {"type": "betaGroups", "attributes": {**base, **link}, "relationships": rel}})["data"]
    except ApiError:
        # 有的帳號要等第一個 build 審核通過才開得了公開連結：先建群組，過了再開
        g = call("POST", "/betaGroups", {"data": {"type": "betaGroups", "attributes": base, "relationships": rel}})["data"]
    summary(f"- 建了外部測試群組「{GROUP}」")
    return g


def ensure_link(group):
    a = group["attributes"]
    if a.get("publicLinkEnabled") and a.get("publicLink"):
        return a["publicLink"], None
    try:
        g = call("PATCH", f"/betaGroups/{group['id']}", {"data": {"type": "betaGroups", "id": group["id"], "attributes": {
            "publicLinkEnabled": True, "publicLinkLimitEnabled": True, "publicLinkLimit": a.get("publicLinkLimit") or LIMIT}}})["data"]
        return g["attributes"].get("publicLink"), None
    except ApiError as e:
        return None, apple_error(e)


# ── build ────────────────────────────────────────────────────────────────────

def pick_build(app_id, version, number):
    query = {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 10}
    if number:
        query["filter[version]"] = number
    else:
        query["filter[preReleaseVersion.version]"] = version
    builds = call("GET", "/builds", query=query).get("data", [])
    ok = [b for b in builds if b["attributes"].get("processingState") == "VALID" and not b["attributes"].get("expired")]
    if not ok:
        what = f"build {number}" if number else f"{version} 處理好的 build"
        summary(f"### ⏸ 找不到 {what}（TestFlight 的流程跑完、Apple 處理好再跑一次）")
        sys.exit(1)
    return ok[0]


def external_state(build_id):
    d = call("GET", f"/builds/{build_id}/buildBetaDetail").get("data") or {}
    return (d.get("attributes") or {}).get("externalBuildState") or ""


def what_to_test(app_id, build_id, locale):
    """外部測試一定要有「測試內容」；TestFlight 的流程寫過就不動"""
    locs = call("GET", f"/builds/{build_id}/betaBuildLocalizations").get("data", [])
    if any((x["attributes"].get("whatsNew") or "").strip() for x in locs):
        return
    text = ("StudioX 測試版：首頁的 Xena 每日重點、收件匣（網站與 LINE 客服）、訂單、商品、流量。"
            "沒有 StudioX 帳號的話，登入畫面點「先看看示範（不用登入）」用示範資料試用。"
            "有問題在 TestFlight 截圖回報，或搖一搖手機。")
    if locs:
        call("PATCH", f"/betaBuildLocalizations/{locs[0]['id']}", {"data": {
            "type": "betaBuildLocalizations", "id": locs[0]["id"], "attributes": {"whatsNew": text}}})
    else:
        call("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})


def give_and_submit(group, build):
    gid, bid = group["id"], build["id"]
    try:
        call("POST", f"/betaGroups/{gid}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
    except ApiError as e:
        # 已經在群組裡
        if e.status != 409 and "already" not in e.detail.lower():
            raise
    state = external_state(bid)
    if state == "READY_FOR_BETA_SUBMISSION":
        try:
            call("POST", "/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions", "relationships": {
                "build": {"data": {"type": "builds", "id": bid}}}}})
            summary("- 送了 Apple 的測試版審核")
        except ApiError as e:
            if "already" not in e.detail.lower():
                summary(f"### ❌ 送測試版審核失敗，Apple 說：\n{apple_error(e)}")
                sys.exit(1)
        state = external_state(bid)
    return state


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--build", default="", help="build 號碼（CFBundleVersion）；沒給就用這個版本最新一個處理好的")
    p.add_argument("--wait", type=int, default=0, help="等測試版審核結果幾分鐘")
    args = p.parse_args()
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(name, "").strip():
            sys.exit(f"缺少 {name}")

    a = app()
    m = meta()
    summary(f"### TestFlight 公開測試（{a['attributes'].get('name')}）")
    contact = store_contact(a["id"])
    info_ok = beta_app_info(a, m, contact)
    review_ok = beta_review_info(a["id"], m, contact)
    if not (info_ok and review_ok):
        summary("### ⏸ 上面缺的補好之後再跑一次")
        sys.exit(1)

    group = public_group(a["id"])
    build = pick_build(a["id"], args.version, args.build)
    number = build["attributes"].get("version")
    what_to_test(a["id"], build["id"], a["attributes"].get("primaryLocale") or m["locale"])
    state = give_and_submit(group, build)
    summary(f"- Build {args.version}（{number}）：{STATES.get(state, state or '?')}")

    deadline = time.time() + args.wait * 60
    while state in PENDING and time.time() < deadline:
        time.sleep(60)
        state = external_state(build["id"])
    if args.wait:
        summary(f"- 現在：{STATES.get(state, state or '?')}")

    group = call("GET", f"/betaGroups/{group['id']}").get("data") or group
    link, error = ensure_link(group)
    if link:
        output("public_link", link)
        ready = state in OPEN
        summary(f"\n### {'✅' if ready else '⏳'} 公開連結：{link}\n"
                + ("用 iPhone 點開，照畫面裝 TestFlight、再按「開始測試」。" if ready else
                   "連結已經可以給人；Apple 審核通過之前點開會看到「目前不接受新的測試員」，過了就能裝。")
                + f"\n人數上限 {group['attributes'].get('publicLinkLimit') or LIMIT}（App Store Connect → TestFlight →「{GROUP}」可以改）")
    else:
        summary(f"\n### ⏳ 公開連結要等測試版審核通過才開得了（Apple 說：{error}）\n過了之後再跑一次就會開好、寫在這裡")
    if state == "BETA_REJECTED":
        summary("### ❌ 測試版審核沒過：App Store Connect → TestFlight → 這個 build 看原因（也會寄信）")
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except ApiError as e:
        summary(f"### ❌ App Store Connect 回了錯誤\n{apple_error(e)}")
        raise
