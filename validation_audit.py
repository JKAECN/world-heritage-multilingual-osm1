# -*- coding: utf-8 -*-
import gzip, csv, json, re, unicodedata
import pandas as pd
csv.field_size_limit(10**9)
BASE = r"C:/Users/Administrator.DESKTOP-UIDK3CD/Desktop/sun-勿删/land"
OUT  = BASE + r"/_review_scratch/revision_sust"
rows=[]
with gzip.open(BASE + "/LAND_PAPER/reanalysis/elements_all.csv.gz","rt",encoding="utf-8",newline="") as f:
    for r in csv.DictReader(f):
        rows.append(r)
el = pd.DataFrame(rows)
def parse_bool(v): return 1 if str(v).strip().lower() in ("true","1") else 0
el["orig"] = el.multilingual_primary.apply(parse_bool)
def parse_ctx(j):
    try: d = json.loads(j)
    except Exception: return {}
    return d if isinstance(d, dict) else {}
el["ctx"] = el.lang_ctx_json.apply(parse_ctx)
el["n_langvals"] = el.ctx.apply(lambda d: sum(1 for k,v in d.items() if k.startswith("name:") and str(v).strip()))
def rederive(row):
    langvals = [str(v).strip() for k,v in row["ctx"].items() if k.startswith("name:") and str(v).strip()]
    dn = str(row["default_name"] or "").strip() or str(row["name"] or "").strip()
    diff = any(lv and dn and lv != dn for lv in langvals)
    return 1 if (diff or len(langvals)>=2) else 0
el["rederived"] = el.apply(rederive, axis=1)
agree = (el.rederived==el.orig).mean()
print("full-pool re-derivation agreement:", round(agree,5), "on", len(el), "| ML rate:", round(el.orig.mean(),4))

SCRIPT_RANGES = [(0x0400,0x04FF,"Cyrillic"),(0x4E00,0x9FFF,"Han"),(0x3040,0x30FF,"Kana"),
                 (0xAC00,0xD7AF,"Hangul"),(0x0600,0x06FF,"Arabic"),(0x0590,0x05FF,"Hebrew"),(0x0370,0x03FF,"Greek")]
def script_of(t):
    t = str(t)
    for a,b,n in SCRIPT_RANGES:
        if any(a<=ord(c)<=b for c in t): return n
    return "Latin" if t.strip() else "None"
def ascii_fold(t):
    return re.sub(r"[^a-z]","",unicodedata.normalize("NFKD",str(t)).encode("ascii","ignore").decode().lower())
ml = el[el.orig==1]; non = el[el.orig==0]
ml_s = ml.sample(n=240, random_state=42); non_s = non.sample(n=120, random_state=42)
audit = pd.concat([ml_s, non_s])
def evidence(row):
    dn = str(row["default_name"] or row["name"] or "")
    langvals = [str(v).strip() for k,v in row["ctx"].items() if k.startswith("name:") and str(v).strip() and str(v).strip()!=str(dn).strip()]
    if not langvals: return "two_lang_fields_no_contrast"
    lv = langvals[0]; sd, sl = script_of(dn), script_of(lv)
    if sd!=sl: return "different_script_pair"
    if dn.strip().lower()==lv.strip().lower(): return "identical_mod_case"
    if ascii_fold(dn) and ascii_fold(dn)==ascii_fold(lv): return "transliteration_candidate"
    if re.search(r"[A-Za-z]", dn) and re.search(r"[A-Za-z]", lv): return "latin_word_difference"
    return "nonlatin_word_difference"
ml_s2 = ml_s.copy(); ml_s2["evidence"] = ml_s2.apply(evidence, axis=1)
ev = ml_s2.evidence.value_counts()
print("audit n:", len(audit), "| agreement on sample:", round((audit.rederived==audit.orig).mean(),4))
print(ev.to_string())
strong = ev.get("different_script_pair",0)+ev.get("latin_word_difference",0)+ev.get("nonlatin_word_difference",0)
print("strong-evidence share:", round(strong/240,4))
reg = pd.read_csv(BASE + "/LAND_FINAL_RESULTS/CITY_DATA_QUALITY.csv", usecols=["city","macro_region"]).drop_duplicates("city")
audit2 = audit.merge(reg, on="city", how="left")
print("audit cities:", audit2.city.nunique(), "| by region:", dict(audit2.macro_region.value_counts()))
print("non-ML with >=2 lang fields:", int((non_s.n_langvals>=2).sum()), "| non-ML rederived=1:", int((non_s.rederived==1).sum()))
ws = pd.concat([ml_s2.assign(stratum="multilingual"), non_s.assign(stratum="non_multilingual")])
ws[["city","osm_type","osm_id","default_name","lang_ctx_json","orig","rederived","stratum","evidence"]].to_csv(OUT + "/validation_audit_worksheet.csv", index=False)
json.dump({"n_pool": int(len(el)), "agreement_fullpool": round(float(agree),5),
  "audit_n": int(len(ws)), "audit_agreement": round(float((audit.rederived==audit.orig).mean()),5),
  "evidence_counts": {k:int(v) for k,v in ev.items()},
  "strong_share": round(float(strong/240),4), "audit_cities": int(audit2.city.nunique()),
  "nonml_with2lang": int((non_s.n_langvals>=2).sum())},
  open(OUT+"/audit_summary.json","w"), indent=1)
print("worksheet saved:", len(ws))
