"""
App Store 上架（.github/workflows/appstore.yml）：用 App Store Connect API 把這一版的上架資料準備好，要的話直接送審。

  python3 ci/appstore.py prepare --version 1.1            上架資料、截圖、選 build、審核說明（不送審）
  python3 ci/appstore.py prepare --version 1.1 --submit   同上，然後送審

做的事：
  1. 這一版（App Store 版本）：沒有就建一個，版本號照 Xcode 的 MARKETING_VERSION；審核通過後由你手動發布
  2. 文字：副標題、描述、宣傳文字、關鍵字、支援網址、行銷網址、隱私權政策網址、版權、分類（ci/appstore/metadata.json）
  3. 年齡分級：都選「無」（商用工具，沒有成人內容）
  4. 截圖：docs/appstore/iphone69/（6.9 吋 iPhone）、docs/appstore/ipad13/（13 吋 iPad）的 .jpg／.png，照檔名順序、整組換掉
  5. 這一版的 build：最新一個處理好的
  6. 審核說明（示範模式怎麼進去、刪除帳號在哪）
  7. 價格：免費；上架地區：全部國家與地區（中國大陸要 ICP 備案，先不上），之後新開的地區自動上架
  8. --submit：送審

API 做不到、要在 App Store Connect 網頁上做一次的：App 隱私權（資料蒐集問卷）、審核聯絡人（姓名、電話、Email）。
送審前會檢查，缺了就在摘要列出來、不送。
"""
import argparse
import glob
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from asc import ApiError, BUNDLE_ID, apple_error, call, summary  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
SHOT_SETS = [("iphone69", "APP_IPHONE_67", "6.9 吋 iPhone"), ("ipad13", "APP_IPAD_PRO_3GEN_129", "13 吋 iPad")]


def meta():
    with open(os.path.join(HERE, "appstore", "metadata.json"), encoding="utf-8") as f:
        return json.load(f)


def data(r):
    return r.get("data") or []


# ── 版本 ─────────────────────────────────────────────────────────────────────

def app_id():
    apps = data(call("GET", "/apps", query={"filter[bundleId]": BUNDLE_ID, "limit": 1}))
    if not apps:
        summary("### ❌ App Store Connect 上沒有這個 App（先跑一次 TestFlight 的流程）")
        sys.exit(1)
    return apps[0]["id"]


def version_for(app, version, m):
    found = data(call("GET", f"/apps/{app}/appStoreVersions", query={"filter[platform]": "IOS", "limit": 20}))
    editable = [v for v in found if v["attributes"].get("appStoreState") in EDITABLE]
    if editable:
        v = editable[0]
        if v["attributes"].get("versionString") != version:
            call("PATCH", f"/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"versionString": version}}})
        summary(f"- 版本 {version}：用現有的（{v['attributes'].get('appStoreState')}）")
    else:
        live = [v for v in found if v["attributes"].get("appStoreState") in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE")]
        if live:
            summary(f"### ⏸ 版本 {live[0]['attributes'].get('versionString')} 正在審核或等你發布（{live[0]['attributes'].get('appStoreState')}），先不動")
            sys.exit(0)
        v = call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}},
        }})["data"]
        summary(f"- 版本 {version}：新建")
    call("PATCH", f"/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {
        "copyright": m["copyright"], "releaseType": "MANUAL",
    }}})
    return v["id"]


# ── 文字 ─────────────────────────────────────────────────────────────────────

def version_texts(version_id, m):
    locs = data(call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", query={"limit": 50}))
    loc = next((x for x in locs if x["attributes"]["locale"] == m["locale"]), None)
    attrs = {
        "description": m["description"], "keywords": m["keywords"], "promotionalText": m["promotionalText"],
        "supportUrl": m["supportUrl"], "marketingUrl": m["marketingUrl"],
    }
    if loc:
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
        loc_id = loc["id"]
    else:
        loc_id = call("POST", "/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations", "attributes": {"locale": m["locale"], **attrs},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
        }})["data"]["id"]
    others = [x["attributes"]["locale"] for x in locs if x["attributes"]["locale"] != m["locale"]]
    summary(f"- 描述、關鍵字、宣傳文字、網址（{m['locale']}）" + (f"；其他語言 {', '.join(others)} 沒有動" if others else ""))
    return loc_id


def app_info(app, m):
    infos = data(call("GET", f"/apps/{app}/appInfos", query={"limit": 10}))
    info = next((i for i in infos if i["attributes"].get("appStoreState") in EDITABLE or i["attributes"].get("state") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED")), infos[0] if infos else None)
    if not info:
        summary("- ⚠️ 找不到 App 資訊（appInfo）")
        return
    try:
        call("PATCH", f"/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": m["primaryCategory"]}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": m["secondaryCategory"]}},
        }}})
        summary(f"- 分類：{m['primaryCategory']}／{m['secondaryCategory']}")
    except ApiError as e:
        summary(f"- ⚠️ 分類沒設定成功：{apple_error(e)}")
    locs = data(call("GET", f"/appInfos/{info['id']}/appInfoLocalizations", query={"limit": 50}))
    loc = next((x for x in locs if x["attributes"]["locale"] == m["locale"]), None)
    attrs = {"subtitle": m["subtitle"], "privacyPolicyUrl": m["privacyPolicyUrl"]}
    if loc:
        call("PATCH", f"/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
        summary(f"- App 名稱：{loc['attributes'].get('name')}；副標題、隱私權政策網址已設定")
    else:
        summary(f"- ⚠️ App 資訊沒有 {m['locale']} 這個語言（主要語言不是繁體中文？）")
    age_rating(info["id"])


# 年齡分級的欄位（Apple 會加新的）：程度類選「無」、是非類選「否」。
# 唯一的「是」：可以傳訊息給別人（專人在 App 裡回覆網站、LINE 的客人）
AGE_ENUMS = {
    "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons", "horrorOrFearThemes",
    "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
    "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic",
}
AGE_BOOLS = {"gambling", "unrestrictedWebAccess", "lootBox", "advertising", "userGeneratedContent", "healthOrWellnessTopics",
             "parentalControls", "ageAssurance", "seventeenPlus"}
AGE_YES = {"messagingAndChat"}


def age_rating(info_id):
    """年齡分級：照 Apple 回的欄位填（商用工具，沒有成人內容）；填不了就請你在網頁上填"""
    try:
        decl = call("GET", f"/appInfos/{info_id}/ageRatingDeclaration").get("data")
    except ApiError as e:
        summary(f"- ⚠️ 讀不到年齡分級：{apple_error(e)}")
        return
    if not decl:
        return
    attrs = {}
    for k, v in decl["attributes"].items():
        # 「分級覆寫」（ageRatingOverride／V2、韓國）和兒童分類保持 Apple 的預設：新舊兩個覆寫欄位不能一起送
        if "override" in k.lower() or k == "kidsAgeBand":
            continue
        if k in AGE_YES:
            attrs[k] = True
        elif isinstance(v, bool) or (v is None and k in AGE_BOOLS):
            attrs[k] = False
        elif isinstance(v, str) or (v is None and k in AGE_ENUMS):
            if k in AGE_ENUMS or v in ("NONE", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE", "INFREQUENT", "FREQUENT"):
                attrs[k] = "NONE"
    try:
        call("PATCH", f"/ageRatingDeclarations/{decl['id']}", {"data": {"type": "ageRatingDeclarations", "id": decl["id"], "attributes": attrs}})
        summary("- 年齡分級：成人內容類都選「無」；「可以傳訊息給別人」選是（專人回覆客人）")
    except ApiError as e:
        summary(f"- ⚠️ 年齡分級要在網頁上填（App 資訊 → 年齡分級）：{apple_error(e)}")


def content_rights(app):
    try:
        call("PATCH", f"/apps/{app}", {"data": {"type": "apps", "id": app, "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    except ApiError as e:
        summary(f"- ⚠️ 內容權利聲明：{apple_error(e)}")


# ── 價格與上架地區 ───────────────────────────────────────────────────────────

# 中國大陸要 ICP 備案號才能上架，先不選（有備案號再加）
SKIP_TERRITORIES = {"CHN"}


def pricing(app):
    """免費：以台灣為基準地區，選價格 0 的價格點"""
    try:
        points = all_pages(f"/apps/{app}/appPricePoints", {"filter[territory]": "TWN", "limit": 200})
        free = next((p for p in points if float(p["attributes"].get("customerPrice") or 1) == 0), None)
        if not free:
            summary("- ⚠️ 找不到免費的價格點，價格要在網頁上設（價格與上架地區 → 免費）")
            return
        call("POST", "/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": app}},
                "baseTerritory": {"data": {"type": "territories", "id": "TWN"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]},
            }},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}],
        })
        summary("- 價格：免費")
    except ApiError as e:
        summary(f"- ⚠️ 價格要在網頁上設（價格與上架地區 → 免費）：{apple_error(e)}")


def all_pages(path, query):
    out, q = [], dict(query)
    while True:
        r = call("GET", path, query=q)
        out += data(r)
        nxt = (r.get("links") or {}).get("next")
        if not nxt:
            return out
        q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(nxt).query))


def availability(app):
    """全部國家與地區（中國大陸除外），之後 Apple 新開的地區也自動上架"""
    try:
        territories = [t["id"] for t in all_pages("/territories", {"limit": 200})]
        existing = None
        try:
            existing = (call("GET", f"/apps/{app}/appAvailabilityV2").get("data") or {}).get("id")
        except ApiError as e:
            if e.status != 404:
                raise
        if not existing:
            call("POST", "/v2/appAvailabilities", {
                "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True}, "relationships": {
                    "app": {"data": {"type": "apps", "id": app}},
                    "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]},
                }},
                # 每個地區都要列（Apple 的規定），不上的（中國大陸）標成 available: false
                "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}",
                              "attributes": {"available": t not in SKIP_TERRITORIES, "releaseDate": None, "preOrderEnabled": False},
                              "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in territories],
            })
            summary(f"- 上架地區：{len(territories) - len(SKIP_TERRITORIES)} 個國家與地區（中國大陸要 ICP 備案，先不上）")
            return
        rows = all_pages(f"/v2/appAvailabilities/{existing}/territoryAvailabilities", {"limit": 200, "include": "territory"})
        turned = 0
        for row in rows:
            tid = ((row.get("relationships") or {}).get("territory") or {}).get("data", {}).get("id")
            if tid and tid not in SKIP_TERRITORIES and not row["attributes"].get("available"):
                call("PATCH", f"/territoryAvailabilities/{row['id']}", {"data": {"type": "territoryAvailabilities", "id": row["id"], "attributes": {"available": True}}})
                turned += 1
        summary(f"- 上架地區：全部國家與地區（中國大陸除外）{f'，這次打開 {turned} 個' if turned else ''}")
    except ApiError as e:
        summary(f"- ⚠️ 上架地區要在網頁上設（價格與上架地區 → 全部國家或地區）：{apple_error(e)}")


# ── 截圖 ─────────────────────────────────────────────────────────────────────

def upload_shot(set_id, path):
    size = os.path.getsize(path)
    name = os.path.basename(path)
    shot = call("POST", "/appScreenshots", {"data": {
        "type": "appScreenshots", "attributes": {"fileName": name, "fileSize": size},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
    }})["data"]
    with open(path, "rb") as f:
        blob = f.read()
    for op in shot["attributes"].get("uploadOperations") or []:
        part = blob[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders") or []})
        with urllib.request.urlopen(req, timeout=120) as r:
            r.read()
    call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"], "attributes": {
        "uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
    }}})
    return shot["id"]


def screenshots(loc_id):
    sets = data(call("GET", f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", query={"limit": 50}))
    for folder, display, label in SHOT_SETS:
        files = sorted(glob.glob(os.path.join(ROOT, "docs", "appstore", folder, "*.png")) + glob.glob(os.path.join(ROOT, "docs", "appstore", folder, "*.jpg")))[:10]
        if not files:
            summary(f"- ⚠️ 沒有 {label} 的截圖（docs/appstore/{folder}/）")
            continue
        s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == display), None)
        if s is None:
            s = call("POST", "/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
            }})["data"]
        # 整組換掉
        for old in data(call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots", query={"limit": 50})):
            call("DELETE", f"/appScreenshots/{old['id']}")
        ids = [upload_shot(s["id"], f) for f in files]
        # Apple 處理完才算數
        for _ in range(30):
            states = [call("GET", f"/appScreenshots/{i}")["data"]["attributes"].get("assetDeliveryState", {}).get("state") for i in ids]
            if all(st == "COMPLETE" for st in states):
                break
            if any(st == "FAILED" for st in states):
                summary(f"- ❌ {label} 有截圖 Apple 處理失敗（尺寸不對？）")
                break
            time.sleep(4)
        summary(f"- 截圖：{label} {len(ids)} 張")


# ── build、審核說明、送審 ────────────────────────────────────────────────────

def attach_build(app, version_id, version):
    builds = data(call("GET", "/builds", query={
        "filter[app]": app, "filter[preReleaseVersion.version]": version, "sort": "-uploadedDate", "limit": 5,
    }))
    ok = [b for b in builds if b["attributes"].get("processingState") == "VALID" and not b["attributes"].get("expired")]
    if not ok:
        summary(f"- ⚠️ 還沒有處理好的 {version} build（TestFlight 的流程跑完、Apple 處理好再跑一次）")
        return False
    b = ok[0]
    call("PATCH", f"/appStoreVersions/{version_id}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    summary(f"- Build：{version}（{b['attributes'].get('version')}）")
    return True


def review_detail(version_id, m):
    attrs = {"notes": m["reviewNotes"], "demoAccountRequired": False}
    try:
        existing = call("GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
    except ApiError:
        existing = None
    if existing:
        call("PATCH", f"/appStoreReviewDetails/{existing['id']}", {"data": {"type": "appStoreReviewDetails", "id": existing["id"], "attributes": attrs}})
        detail = existing["attributes"]
    else:
        created = call("POST", "/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
        }})["data"]
        detail = created["attributes"]
    missing = [label for key, label in (("contactFirstName", "名"), ("contactLastName", "姓"), ("contactPhone", "電話"), ("contactEmail", "Email")) if not detail.get(key)]
    summary("- 審核說明（示範模式怎麼進去）已填" + (f"；⚠️ 審核聯絡人還沒填：{'、'.join(missing)}" if missing else ""))
    return not missing


def submit(app, version_id):
    try:
        sub = call("POST", "/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}},
        }})["data"]
    except ApiError as e:
        # 已經有一個還沒送出的：拿來用
        open_subs = data(call("GET", "/reviewSubmissions", query={"filter[app]": app, "filter[state]": "READY_FOR_REVIEW", "limit": 1}))
        if not open_subs:
            summary(f"### ❌ 沒辦法建立送審：{apple_error(e)}")
            sys.exit(1)
        sub = open_subs[0]
    try:
        call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
            },
        }})
    except ApiError as e:
        if "already" not in e.detail.lower():
            summary(f"### ❌ 這一版不能送審，Apple 說：\n{apple_error(e)}\n\n"
                    "常見的原因：App 隱私權問卷還沒發布、價格或上架地區還沒設定、審核聯絡人沒填。")
            sys.exit(1)
    try:
        call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    except ApiError as e:
        summary(f"### ❌ 送審失敗，Apple 說：\n{apple_error(e)}\n\n"
                "常見的原因：App 隱私權問卷還沒發布、價格或上架地區還沒設定、審核聯絡人沒填。")
        sys.exit(1)
    summary("### ✅ 已送審：App Store Connect 的狀態會變成「等待審核」，通常 1～2 天內有結果")


def prepare(args):
    m = meta()
    app = app_id()
    summary(f"### App Store {args.version}")
    version_id = version_for(app, args.version, m)
    loc_id = version_texts(version_id, m)
    app_info(app, m)
    content_rights(app)
    pricing(app)
    availability(app)
    if not args.skip_screenshots:
        screenshots(loc_id)
    has_build = attach_build(app, version_id, args.version)
    contact_ok = review_detail(version_id, m)
    summary("\n**還要在 App Store Connect 網頁上做一次的**（API 做不到）：App 隱私權問卷"
            + ("" if contact_ok else "、審核聯絡人（姓名、電話、Email）"))
    if args.submit:
        if not has_build:
            summary("### ⏸ 沒有 build，先不送審")
            sys.exit(1)
        submit(app, version_id)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    pp = sub.add_parser("prepare")
    pp.add_argument("--version", required=True)
    pp.add_argument("--submit", action="store_true")
    pp.add_argument("--skip-screenshots", action="store_true")
    args = p.parse_args()
    try:
        prepare(args)
    except ApiError as e:
        summary(f"### ❌ App Store Connect 回了錯誤\n{apple_error(e)}")
        raise


if __name__ == "__main__":
    main()
