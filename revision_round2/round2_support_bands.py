"""
round2_support_bands.py
=======================
Compute the FULL eight-band pooled distance series after each pre-stated
minimum-support exclusion (<10 / <30 eligible grids). Reviewer 1, Major
comment 4 asked for "city-equal means, distance-band series, and the main
model"; the previous Appendix B Table B2 reported only the two endpoints.

Uses exactly the same frozen inputs, primary sample, band definition and
exclusion rule as round2_reanalysis.py, so every number is consistent with
Table 7 / Table B1 / Table B2.
"""
import json
import os

import numpy as np
import pandas as pd

BASE = r"C:/Users/Administrator.DESKTOP-UIDK3CD/Desktop/sun-勿删/land"
LIB = os.path.join(BASE, "LAND_FINAL_RESULTS", "FINAL_60cities_grid500m.csv")
V7 = os.path.join(BASE, "LAND_PAPER", "reanalysis_v7", "grid_v7_metrics.csv")
OUT = os.path.join(BASE, "_review_scratch", "round2_support_bands.json")

lib = pd.read_csv(LIB, low_memory=False)
v7 = pd.read_csv(V7, low_memory=False)
need = ["grid_id", "n_multilingual_corrected", "n_multilingual_notranslit"]
d = lib.merge(v7[need], on="grid_id", how="left", validate="one_to_one")
assert d[need[1:]].isna().sum().sum() == 0
e = d[d["n_named_poi"] >= 5].copy().reset_index(drop=True)
e["band"] = np.clip(np.floor(e["heritage_distance_km"]).astype(int), 0, 7)

city_stats = e.groupby("city").size().rename("grids")
labels = ["%d–%d" % (k, k + 1) for k in range(8)]
rules = [("all 59", list(city_stats.index)),
         ("cities with ≥10 eligible grids", list(city_stats[city_stats >= 10].index)),
         ("cities with ≥30 eligible grids", list(city_stats[city_stats >= 30].index))]

rows = []
for tag, keep in rules:
    dd = e[e.city.isin(keep)]
    vals = []
    for k in range(8):
        s = dd[dd.band == k]
        vals.append(round(float(s.n_multilingual_primary.sum() / s.n_named_poi.sum()), 4)
                    if len(s) and s.n_named_poi.sum() > 0 else None)
    rows.append({"tag": tag, "cities": len(keep), "grids": int(len(dd)),
                 "named": int(dd.n_named_poi.sum()), "bands": vals})
    print(tag, "cities", len(keep), "grids", len(dd), "bands", vals)

res = {"labels": labels, "rows": rows,
       "definition": "pooled named-feature-weighted primary multilingual proportion"}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
print("saved", OUT)
