# -*- coding: utf-8 -*-
"""Round-2 reviewer response: reproducible re-analyses.

Inputs (all archived, read-only):
  LAND_FINAL_RESULTS/FINAL_60cities_grid500m.csv
  LAND_PAPER/reanalysis_v7/grid_v7_metrics.csv
Outputs:
  _review_scratch/round2_results.json
  _review_scratch/round2_band_table.csv
  _review_scratch/round2_support_table.csv
"""
import json, os
import numpy as np
import pandas as pd
import patsy
import statsmodels.api as sm
from scipy import stats

B = r"C:/Users/Administrator.DESKTOP-UIDK3CD/Desktop/sun-勿删/land"
LIB = os.path.join(B, "LAND_FINAL_RESULTS", "FINAL_60cities_grid500m.csv")
V7 = os.path.join(B, "LAND_PAPER", "reanalysis_v7", "grid_v7_metrics.csv")
OUT = os.path.join(B, "_review_scratch")
R = {}

LAND_COLS = ["land_commercial_retail", "land_residential", "land_recreation_green",
             "land_institutional", "land_transportation"]
RHS = ("log1p_visitor + land_commercial_retail + land_residential"
       " + land_recreation_green + land_institutional + land_transportation"
       " + log1p_poi_density_km2 + {spline} + C(city)")

lib = pd.read_csv(LIB, low_memory=False)
v7 = pd.read_csv(V7, low_memory=False)
need = ["grid_id", "n_multilingual_corrected", "n_multilingual_notranslit",
        "narrow_A_density_km2", "narrow_B_density_km2", "grid_i", "grid_j"]
d = lib.merge(v7[need], on="grid_id", how="left", validate="one_to_one")
# two zero-area Cordoba boundary cells have undefined density; they are outside the
# >=5 named-feature primary sample, so filling with 0 cannot affect any reported value.
for c in ("narrow_A_density_km2", "narrow_B_density_km2"):
    d[c] = d[c].fillna(0.0)
assert d[need[1:]].isna().sum().sum() == 0
d["log1p_poi_density_km2"] = np.log1p(d["poi_density_km2"])
e = d[d["n_named_poi"] >= 5].copy().reset_index(drop=True)

# ---------- 0. pool reconciliation ----------
R["pool"] = {
    "all_grids": int(len(d)),
    "all_named_features": int(d.n_named_poi.sum()),
    "eligible_grids": int(len(e)),
    "eligible_named_features": int(e.n_named_poi.sum()),
    "eligible_multilingual_primary": int(e.n_multilingual_primary.sum()),
    "eligible_multilingual_strict": int(e.n_multilingual_strict.sum()),
    "cities": int(e.city.nunique()),
    "morocco_cities": ["Marrakesh", "Fez"],
}

# ---------- 1. distance-band series under four definitions ----------
e["band"] = np.clip(np.floor(e["heritage_distance_km"]).astype(int), 0, 7)
label = lambda k: "%d-%d" % (k, k + 1)
DEF = {
    "primary": "n_multilingual_primary",
    "corrected": "n_multilingual_corrected",
    "notranslit": "n_multilingual_notranslit",
    "auxiliary": "n_multilingual_strict",
}
bands = []
for k in range(8):
    s = e[e.band == k]
    rec = {"band": label(k), "cities": int(s.city.nunique()), "grids": int(len(s)),
           "named": int(s.n_named_poi.sum())}
    for name, col in DEF.items():
        rec["ml_" + name] = int(s[col].sum())
        rec["pooled_" + name] = float(s[col].sum() / s.n_named_poi.sum())
    bands.append(rec)
band_df = pd.DataFrame(bands)

# fixed 44-city common-support subset (primary sample, all 8 bands)
city_band = e.groupby("city")["band"].nunique()
common = sorted(city_band[city_band == 8].index)
R["common_support_cities"] = len(common)
cs = e[e.city.isin(common)]
for name, col in DEF.items():
    band_df["equal44_" + name] = [
        float(np.mean([g[col].sum() / g.n_named_poi.sum() for _, g in cs[cs.band == k].groupby("city")]))
        for k in range(8)]

# endpoint city comparison: cities present in both 0-1 and 7-8
ends = e[e.band.isin([0, 7])]
pair = []
for city, g in ends.groupby("city"):
    if g.band.nunique() == 2:
        a = g[g.band == 0].n_multilingual_primary.sum() / g[g.band == 0].n_named_poi.sum()
        b = g[g.band == 7].n_multilingual_primary.sum() / g[g.band == 7].n_named_poi.sum()
        pair.append((city, a, b))
R["endpoint_comparison"] = {
    "cities": len(pair),
    "lower_outer_primary": int(sum(1 for _, a, b in pair if b < a)),
}
for name, col in DEF.items():
    cnt = 0
    for city, g in ends.groupby("city"):
        if g.band.nunique() != 2:
            continue
        a = g[g.band == 0][col].sum() / g[g.band == 0].n_named_poi.sum()
        b = g[g.band == 7][col].sum() / g[g.band == 7].n_named_poi.sum()
        cnt += (b < a)
    R["endpoint_comparison"]["lower_outer_" + name] = int(cnt)
band_df.to_csv(os.path.join(OUT, "round2_band_table.csv"), index=False)
R["band_table"] = band_df.round(6).to_dict("records")

# ---------- 2. city-equal means, low-support exclusions ----------
city_stats = e.groupby("city").agg(
    grids=("grid_id", "size"), named=("n_named_poi", "sum"),
    ml_primary=("n_multilingual_primary", "sum"),
    ml_corrected=("n_multilingual_corrected", "sum"),
    ml_notranslit=("n_multilingual_notranslit", "sum"),
    ml_auxiliary=("n_multilingual_strict", "sum"),
    region=("macro_region", "first"))
for name in DEF:
    city_stats["share_" + name] = city_stats["ml_" + name] / city_stats["named"]

def summarise(sub, tag):
    dd = e[e.city.isin(sub)]
    rec = {"tag": tag, "cities": len(sub), "grids": int(len(dd)),
           "named": int(dd.n_named_poi.sum())}
    for name, col in DEF.items():
        rec["city_equal_" + name] = float(city_stats.loc[sub, "share_" + name].mean())
        rec["pooled_" + name] = float(dd[col].sum() / dd.n_named_poi.sum())
        for k in (0, 7):
            s = dd[dd.band == k]
            rec["band%s_pooled_%s" % (k, name)] = float(s[col].sum() / s.n_named_poi.sum())
    return rec

support_rows = [summarise(list(city_stats.index), "all 59")]
for t in (10, 30):
    keep = list(city_stats.index[city_stats.grids >= t])
    support_rows.append(summarise(keep, "cities with >=%d eligible grids" % t))
    R["excluded_below_%d" % t] = sorted(set(city_stats.index) - set(keep))
    R["n_excluded_below_%d" % t] = len(set(city_stats.index) - set(keep))
R["support_table"] = support_rows
pd.DataFrame(support_rows).to_csv(os.path.join(OUT, "round2_support_table.csv"), index=False)
R["sparse_cities"] = city_stats.sort_values("grids")[["grids", "named", "share_primary"]].head(12).round(4).to_dict("index")
R["city_equal_means_by_region"] = {n: float(g.share_primary.mean()) for n, g in city_stats.groupby("region")}

# ---------- 3. quasi-binomial GLM with city-clustered sandwich ----------
x = e["heritage_distance_km"].values
# patsy cr(knots=...) takes INNER knots only; boundary knots come from
# lower_bound / upper_bound (fixed here to the full primary-sample range so
# every subsample uses the same basis as the published R splines::ns(df=4)).
knots = [float(np.min(x))] + [float(np.quantile(x, q)) for q in (0.25, 0.5, 0.75)] + [float(np.max(x))]
SPLINE = ('cr(heritage_distance_km, knots=%s, lower_bound=%.12f, upper_bound=%.12f, '
          'constraints="center")') % (repr([round(k, 12) for k in knots[1:-1]]),
                                      knots[0], knots[-1])
R["spline_knots"] = [round(k, 6) for k in knots]

def fit_model(data, outcome="n_multilingual_primary", visitor="visitor_poi_density_km2"):
    dd = data.copy()
    dd["log1p_visitor"] = np.log1p(dd[visitor].values)
    dd["_fail"] = dd["n_named_poi"] - dd[outcome]
    X = patsy.dmatrix(RHS.format(spline=SPLINE), dd, return_type="dataframe")
    Xv, names = X.values, list(X.columns)
    keep = list(range(Xv.shape[1]))
    while np.linalg.matrix_rank(Xv[:, keep]) < len(keep):
        Q, RR = np.linalg.qr(Xv[:, keep])
        keep.pop(int(np.argmin(np.abs(np.diag(RR)))))
    Xv, names = Xv[:, keep], [names[j] for j in keep]
    y = np.column_stack([dd[outcome].values.astype(float), dd["_fail"].values.astype(float)])
    res = sm.GLM(y, Xv, family=sm.families.Binomial()).fit(scale="X2", maxiter=200)
    beta = np.asarray(res.params, float)
    n = dd["n_named_poi"].values.astype(float); s = dd[outcome].values.astype(float)
    mu = np.asarray(res.fittedvalues, float).ravel(); N = len(dd)
    var = n * mu * (1 - mu)
    phi = float(np.sum((s - n * mu) ** 2 / var) / (N - len(keep)))
    u = Xv * (s - n * mu)[:, None]
    A = Xv.T @ (Xv * var[:, None]); Ainv = np.linalg.inv(A)
    groups = pd.factorize(dd["city"].values)[0]; G = int(groups.max() + 1)
    ug = np.zeros((G, Xv.shape[1])); np.add.at(ug, groups, u)
    corr = (G / (G - 1.0)) * ((N - 1.0) / float(N - len(keep)))
    V = Ainv @ (ug.T @ ug) @ Ainv * corr
    se = np.sqrt(np.clip(np.diag(V), 0, None))
    i = names.index("log1p_visitor")
    tcrit = stats.t.ppf(0.975, G - 1)
    pval = float(2 * stats.t.sf(abs(beta[i] / se[i]), G - 1)) if se[i] > 0 else float("nan")
    return {"beta": float(beta[i]), "se": float(se[i]),
            "ci": [float(beta[i] - tcrit * se[i]), float(beta[i] + tcrit * se[i])],
            "p": pval,
            "N": int(N), "cities": int(G), "dispersion": phi}

R["model_primary"] = fit_model(e)
specs = [
    ("Primary model (n_named_feat >= 5)", e, "n_multilingual_primary", "visitor_poi_density_km2"),
    ("R1 stricter multilingual definition", e, "n_multilingual_strict", "visitor_poi_density_km2"),
    ("R2 n_named_feat >= 10", e[e.n_named_poi >= 10], "n_multilingual_primary", "visitor_poi_density_km2"),
    ("R2 n_named_feat >= 20", e[e.n_named_poi >= 20], "n_multilingual_primary", "visitor_poi_density_km2"),
    ("R3 land-use coverage >= 0.25", e[e.landuse_mapped_coverage >= 0.25], "n_multilingual_primary", "visitor_poi_density_km2"),
    ("R3 land-use coverage >= 0.50", e[e.landuse_mapped_coverage >= 0.50], "n_multilingual_primary", "visitor_poi_density_km2"),
    ("R4 Europe", e[e.macro_region == "Europe"], "n_multilingual_primary", "visitor_poi_density_km2"),
    ("R4 Asia-MENA", e[e.macro_region == "Asia-MENA"], "n_multilingual_primary", "visitor_poi_density_km2"),
    ("R4 Latin America", e[e.macro_region == "Latin America"], "n_multilingual_primary", "visitor_poi_density_km2"),
]
R["table9"] = {}
for tag, dd, outcome, vis in specs:
    try:
        R["table9"][tag] = fit_model(dd, outcome, vis)
    except Exception as ex:
        R["table9"][tag] = {"error": str(ex)}
for t in (10, 30):
    keep = city_stats.index[city_stats.grids >= t]
    R["model_excl_below_%d" % t] = fit_model(e[e.city.isin(keep)])

# ---------- 4. collinearity / VIF ----------
def vif_and_r(visitor):
    a = np.log1p(e[visitor].values)
    b = np.log1p(e["poi_density_km2"].values)
    r = float(np.corrcoef(a, b)[0, 1])
    others = np.column_stack([np.log1p(e["poi_density_km2"].values)] +
                             [e[c].values for c in LAND_COLS] +
                             [e["heritage_distance_km"].values])
    Z = np.column_stack([np.ones(len(e)), others])
    coef = np.linalg.lstsq(Z, a, rcond=None)[0]
    r2 = 1 - float(np.sum((a - Z @ coef) ** 2) / np.sum((a - a.mean()) ** 2))
    return {"r_visitor_named_density": r, "simple_VIF": float(1 / (1 - r ** 2)),
            "full_model_R2": r2, "full_model_VIF": float(1 / (1 - r2))}
R["vif_wide"] = vif_and_r("visitor_poi_density_km2")
R["vif_narrowB"] = vif_and_r("narrow_B_density_km2")

# ---------- 5. Figure 3 caption values and richness outlier ----------
fig3 = {}
for c in ["Vienna", "Istanbul", "Macao", "Cusco"]:
    g = e[e.city == c]
    fig3[c] = {"grids": int(len(g)),
               "feature_weighted": float(g.n_multilingual_primary.sum() / g.n_named_poi.sum()),
               "grid_equal_mean": float(g.multilingual_visibility_primary.mean()),
               "city_equal_share": float(city_stats.loc[c, "share_primary"])}
R["figure3"] = fig3
mx = d.loc[d.language_richness.idxmax()]
R["richness_outlier"] = {"grid_id": str(mx.grid_id), "city": str(mx.city),
                         "value": int(mx.language_richness),
                         "n_named": int(mx.n_named_poi)}

# ---------- 6. descriptive city-cluster bootstrap for endpoints ----------
rng = np.random.default_rng(20261111)
cities = sorted(e.city.unique())
gi = {c: g[["band", "n_named_poi", "n_multilingual_primary"]].values for c, g in e.groupby("city")}
boot = {0: [], 7: []}
for _ in range(2000):
    pick = rng.choice(cities, size=len(cities), replace=True)
    for k in (0, 7):
        num = den = 0.0
        for c in pick:
            a = gi[c]; m = a[a[:, 0] == k]
            if len(m):
                num += m[:, 2].sum(); den += m[:, 1].sum()
        boot[k].append(num / den if den else np.nan)
R["bootstrap_CI"] = {}
for k in (0, 7):
    arr = np.array(boot[k], float)
    obs = bands[k]["pooled_primary"]
    R["bootstrap_CI"][label(k)] = {"observed": obs,
        "ci95": [float(np.nanpercentile(arr, 2.5)), float(np.nanpercentile(arr, 97.5))]}
diff = np.array(boot[0], float) - np.array(boot[7], float)
R["bootstrap_CI"]["difference"] = {
    "observed": bands[0]["pooled_primary"] - bands[7]["pooled_primary"],
    "ci95": [float(np.nanpercentile(diff, 2.5)), float(np.nanpercentile(diff, 97.5))]}

# ---------- 7. limited spatial sensitivity ----------
# (a) exclude serial / multi-component properties named by the reviewer
serial = ["Seoul", "Isfahan", "Hue", "Kyoto", "Quanzhou", "Mexico City"]
R["serial_cities_excluded"] = [c for c in serial if c in set(city_stats.index)]
sens = {}
dd = e[~e.city.isin(serial)]
for k in (0, 7):
    s = dd[dd.band == k]
    sens["exclude_serial_band%d" % k] = float(s.n_multilingual_primary.sum() / s.n_named_poi.sum())
# (b) re-anchor at each city's most name-dense eligible grid (grid_i/grid_j lattice)
ee = e.copy()
anchors = {}
for c, g in ee.groupby("city"):
    row = g.loc[g.n_named_poi.idxmax()]
    anchors[c] = (float(row.grid_i), float(row.grid_j))
ee["alt_km"] = [0.5 * np.hypot(r.grid_i - anchors[r.city][0], r.grid_j - anchors[r.city][1])
                for r in ee.itertuples()]
for k in (0, 7):
    s = ee[(ee.alt_km >= k) & (ee.alt_km < k + 1)]
    sens["reanchor_band%d" % k] = {"pooled": float(s.n_multilingual_primary.sum() / s.n_named_poi.sum()),
                                    "grids": int(len(s)), "cities": int(s.city.nunique())}
R["spatial_sensitivity"] = sens

# ---------- 8. Table 3 scope counts (cities in which each rule fired) ----------
contrib = pd.read_csv(os.path.join(B, "LAND_PAPER", "reanalysis_v7", "audit_correction_contribution.csv"))
R["table3_scope_cities"] = {k: int(v) for k, v in contrib.groupby("cat_rm").city.nunique().items()}
R["table3_scope_rows"] = {k: int(v) for k, v in contrib.cat_rm.value_counts().items()}

with open(os.path.join(OUT, "round2_results.json"), "w", encoding="utf-8") as f:
    json.dump(R, f, ensure_ascii=False, indent=1, default=float)
print(json.dumps({k: R[k] for k in ["pool", "common_support_cities", "endpoint_comparison",
    "model_primary", "vif_wide", "vif_narrowB", "figure3", "richness_outlier",
    "bootstrap_CI", "spatial_sensitivity", "table3_scope_cities"]},
    ensure_ascii=False, indent=1, default=float))
print("saved", os.path.join(OUT, "round2_results.json"))
