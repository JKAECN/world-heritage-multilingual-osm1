# Multilingual Digital Visibility of World Heritage in OpenStreetMap

Replication archive for the manuscript:

> **Cross-City Multilingual Digital Visibility of World Heritage in OpenStreetMap: A 59-City Grid-Based Assessment** (second revised manuscript, 2026)

This repository contains the analysis code, processed datasets, validation records, and figures needed to reproduce every number, table, and figure reported in the revised manuscript and the response to reviewers.

**Round-2 revision note (12 November 2026).** The definitions and disclosure below supersede earlier README wording. The authoritative definitions are those in the manuscript (Sections 2.3–2.4.1 and Appendix B, Table B4); this README reproduces their substance. Second-round verification artefacts are deposited in `revision_round2/` and indexed by `manifest_round2_addendum.yaml`. **The primary grid-level data have not changed**: their SHA-256 hashes remain exactly those recorded in `manifest.yaml` (for example `analysis_sample.csv` = `e0206f38060905c9a525d62eb021e4be919bcc9d5b232146f235e2ecb38291e6`; `grid_v7_metrics.csv` = `9bf9e9850bbd2084e5579271ff99b604d29590fdf0ad3823ff33da53b6aafa6e`).

---

## 1. Study design in brief

- **Scope**: 59 World Heritage city–property pairs in 36 countries (Europe 20, **Asia and North Africa** 20, Latin America 19). "Asia and North Africa" is a geographic grouping of the countries listed in Table A1 of the manuscript only; it carries no civilizational, ethnic, linguistic or cultural meaning, and no inference is drawn from the label. The abbreviation previously used for this grouping does not appear in the revised manuscript, its figures, or this repository.
- **Sample formation**: `UNESCO_60_CITIES_MASTER.csv` contains 60 city–property pairs. One pair, the Historic Centre of Puebla (Mexico), was excluded before analysis because its land-use extraction failed; the failure is recorded verbatim in `ERROR_LOG.csv`. Puebla never entered any pooled, regional or model statistic, so the 19-city / 3,996-grid Latin American subsample is unaffected. The candidate-screening stages that produced the 60-pair master cannot be reconstructed step by step, and no unverifiable intermediate attrition counts are reported.
- **Spatial unit**: 500 m × 500 m projected grid cells within an 8 km window around each UNESCO World Heritage List representative coordinate; 50,506 stored cells in total. Representative coordinates are standardized reference points, not official property boundaries; official boundaries and component coordinates are not present in the archive.
- **Primary analytical sample**: the 15,020 eligible cells with ≥5 function-filtered named OSM features.
- **Outcome — authoritative definitions** (manuscript Sections 2.3–2.4.1; Appendix B Table B4):
  - `primary`: a function-filtered named OSM feature is counted as a multilingual name record if its default `name` differs from the value of at least one explicit `name:<language>` field, **or** if it carries at least two explicit `name:<language>` fields. The grid-level indicator is the proportion of all function-filtered named features meeting this rule.
  - `auxiliary`: counted only when the feature carries at least two explicit `name:<language>` fields. Regional and script variants (for example `name:zh` and `name:zh-Hans`) are collapsed to a common base language code before the test, so the auxiliary rule counts **≥2 distinct base-language fields**, not raw tag occurrences.
  - `corrected`: the primary rule after excluding 2,966 same-language script-variant candidates and 654 records triggered only by typographic differences.
  - `notranslit`: the corrected rule after additionally excluding 3,697 candidate romanization/transliteration records; used as a conservative sensitivity definition, not as a verified error rate.
  - All four definitions describe the **structure of database name fields**, not independently validated linguistic identity, bilingual signage, application rendering, visitor comprehension or governance outcomes. The earlier README shorthand for the primary outcome (a script-count formulation) is withdrawn.
- **Data snapshot**: OpenStreetMap via the Overpass API on **2026-10-17**; UNESCO World Heritage List coordinates (1,273 properties, 2026 DataHub release).

## 2. Reproduction workflow

All original analysis steps are indexed, with SHA-256 hashes and byte sizes, in **`manifest.yaml`**. Verify any file with `sha256sum <file>` against its `sha256` field. Second-round additions are indexed separately in `manifest_round2_addendum.yaml`.

| Step | Script | Inputs → Outputs |
|---|---|---|
| 1 | `01_BUILD_OSM_60_CITIES_FINAL_V2_FIXED.R` | `UNESCO_60_CITIES_MASTER.csv` + Overpass raw extracts → `LAND_FINAL_RESULTS/FINAL_60cities_grid500m.csv`, per-city grids, `CITY_DATA_QUALITY.csv` |
| 2 | `02_ANALYZE_FINAL_DATA_V2_FIXED.R` | step-1 outputs → `LAND_FINAL_RESULTS/ANALYSIS_RESULTS/` |
| 3 | `LAND_PAPER/artifacts/scripts/land_analysis_full.py` | analysis sample → `LAND_PAPER/artifacts/` |
| 4 | `LAND_PAPER/reanalysis/run_reanalysis.py` | analysis sample → `LAND_PAPER/reanalysis/` |
| 5 | `validation_audit.py` | blind coding sheets → `validation_audit_worksheet.csv`, `audit_summary.json` |
| 6 | `LAND_PAPER/reanalysis_v7/reestimate_v7.py` | frozen grid files → city-clustered sandwich standard errors in Tables 6, 8, 9 and B2 (NS4 spline basis). The root-level R scripts archive the original workflow; they are **not** the source of the reported intervals. |
| 7 | `revision_round2/round2_reanalysis.py`, `revision_round2/round2_support_bands.py` | frozen grid files → `round2_results.json`, `round2_band_table.csv`, `round2_support_table.csv`, `round2_support_bands.json` (Appendix B Tables B1–B3) |

**Raw Overpass extracts (~535 MB) are not deposited.** The archived query contains no `[date:]` or Attic filter; the snapshot date (17 October 2026) is recorded in `manifest.yaml` and in the per-city files. Public Overpass endpoints serve a living database, so **exact live re-extraction of that snapshot cannot be guaranteed and is not claimed**. Reproducibility rests on the frozen, checksum-matched grid-level files. The earlier claim that raw extracts could be re-downloaded for a specific historical snapshot date is **withdrawn**.

**Query and feature-pool reconciliation** (manuscript Table B4): the named-feature query is a union of eight `nwr["name"][functional-key]` groups (`tourism`, `amenity`, `shop`, `leisure`, `historic`, `office`, `public_transport`, `railway=station`), returning nodes, ways and relations with `out center`. Land use comes from closed `landuse=*` ways only (no multipolygon relations). From `audit_summary.json`: 572,922 named elements parsed from the raw 60-pair extracts; 4,127 belong to the excluded Puebla pair; 134 were not assigned to a retained grid; **568,661** function-filtered named features were assigned to the 50,506 stored grids; **552,553** fall in the 15,020 eligible grids. Ways and relations are assigned by bounding-box centre, not a geometric centroid, and entities are not deduplicated across OSM element types.

**Grid reconstruction check.** Given only the per-city UTM zone formula (`zone = floor((lon+180)/6)+1`; EPSG 32600+zone north / 32700+zone south), the UNESCO coordinates in `UNESCO_60_CITIES_MASTER.csv`, and the grid indices in `grid_v7_metrics.csv`, the heritage distance of every interior cell can be reconstructed with a maximum absolute error of **3.4 × 10⁻¹⁰ m** across all 59 cities.

## 3. Repository layout

```
manifest.yaml                      SHA-256 / byte-size index of the original analysis files
manifest_round2_addendum.yaml      SHA-256 / byte-size index of second-round additions
01_BUILD_OSM_60_CITIES_FINAL_V2_FIXED.R    step-1 build script
02_ANALYZE_FINAL_DATA_V2_FIXED.R           step-2 analysis script
UNESCO_60_CITIES_MASTER.csv        archived 60-pair candidate master
Coding_Manual.docx                 frozen first-round blind-coding manual (provenance only; see note below)
Coder1_Blind_coded.xlsx            coder-1 blind validation sheet
validation_audit.py                step-5 audit script
validation_audit_worksheet.csv     360-cell audit worksheet
audit_summary.json                 audit summary (n_pool = 572,922)
revision_round2/                   second-round verification artefacts (see Section 5)

LAND_FINAL_RESULTS/
  FINAL_60cities_grid500m.csv      authoritative grid-level dataset (50,506 cells; 59 cities)
  CITY_DATA_QUALITY.csv            per-city data-quality indicators
  ERROR_LOG.csv                    exclusion log: one row (Puebla, land-use extract failed)
  03_city_grid_data/               per-city grid extracts

LAND_PAPER/
  artifacts/analysis_sample.csv    primary sample extract (15,020 cells)
  reanalysis_v7/                   re-analysis tables and clustered-inference script
  reanalysis/bootstrap_cache.npz   (see provenance note below)

validation/
  Land_Distance_Band_Support_Verified.csv
  Land_59_City_Support_Verified.csv
  Land_Distance_Verification_Report.json

figures/                           first-round figure files retained for provenance
  Figure1A_sample_map.png  Figure1B_workflow.png
  Figure2_distance_bands.png  Figure3_city_maps.png
```

**Note on the coding manual.** `Coding_Manual.docx` is retained **byte-for-byte unchanged** as the frozen record of the first-round double-blind validation of the 360-record sample (SHA-256 `c6c75da73721ac908ec828920fc4bc0c2e06daa28b120f6033caf8bb19aac5cd`; registered in `manifest_round2_addendum.yaml` under `frozen_artefacts`, since the original `manifest.yaml` does not index it). It predates the four-definition sensitivity framework and should **not** be used to interpret the outcome variable. See `revision_round2/CODING_MANUAL_SCOPE.md` for its scope, for why its human judgment rule deliberately differs from the programmatic codings, and for the authoritative-definition hierarchy. The authoritative definitions are the four rules in Section 1 above, manuscript Sections 2.3–2.4.1, and Appendix B Table B4.

**Note on figures.** `revision_round2/figures/` holds the redrawn Figure 1(A) (legend "Asia and North Africa (n = 20)") and Figure 3 (panel labels "pooled share"; Macao panel "Macao (Asia and North Africa)"), together with the new Appendix B Figure B1 (four-definition, two-panel, 300 dpi). Where `figures/` and `revision_round2/figures/` differ, the latter are the versions embedded in the revised manuscript; no data point or value was changed by redrawing.

## 4. Provenance-retained files

`pred_distance_gradient.csv`, `gradient_contrast_boot_v7.csv`, and `bootstrap_cache.npz` were generated under a bootstrap prediction pipeline that was **retired during revision** (manuscript Section 4.5). They do not reconcile with the frozen banded counts, are not used by any reported result, and are retained solely for audit traceability. The descriptive city-cluster intervals in Table B3 were computed directly from the frozen grid counts and do not reuse this cache.

## 5. Second-round verification artefacts (`revision_round2/`)

These files were produced by reading the frozen, checksum-matched grid-level files directly; no data value, sample count, estimate or conclusion was changed.

| File | Content |
|---|---|
| `round2_results.json` | Single source for all second-round re-estimates: feature-pool totals (`pool`), eight-band series (`band_table`), 44-city equal-weight series, endpoint comparison, support thresholds, sparse cities, main model and Table 9 coefficients, VIF, bootstrap intervals, spatial sensitivity |
| `round2_band_table.csv` | Machine-readable Table B1: eight 1 km bands × four definitions, pooled and equal-44 shares (12 data columns) |
| `round2_support_table.csv` | Machine-readable Table B2: ≥10 / ≥30 eligible-grid support thresholds and re-estimated models |
| `round2_support_bands.json` | Machine-readable Table B2 (continued): complete eight-band series under all three support rules |
| `round2_reanalysis.py` | Re-estimation script (quasi-binomial GLM, city fixed effects, NS4 spline, city-clustered sandwich SE) |
| `round2_support_bands.py` | Eight-band series under the three support rules |
| `CODING_MANUAL_SCOPE.md` | Scope of the frozen first-round `Coding_Manual.docx`, its checksum, the authoritative-definition hierarchy, and why its human judgment rule deliberately differs from the programmatic codings |
| `figures/round2_fig1a_fixed.png` | Redrawn Figure 1(A) |
| `figures/round2_fig3_fixed.png` | Redrawn Figure 3 |
| `figures/round2_figure_B1.png` | Appendix B Figure B1 |

**Note on a legacy field code.** The frozen source tables use a legacy hyphenated region code for the Asia and North Africa group as the literal value of the `macro_region` column. That value therefore also appears as a filter in `round2_reanalysis.py` and as a JSON key in `round2_results.json`. It is preserved verbatim so that the deposited scripts reproduce the deposited results byte-for-byte from the frozen inputs; changing it would break the checksum-matched baseline. It is a database field code, not the label used in the manuscript: the manuscript and this README use "Asia and North Africa" throughout, and the embedded figures were redrawn accordingly.

Reproduced totals: 50,506 stored grids; 568,661 function-filtered named features in those grids; 15,020 eligible grids; 552,553 named features in eligible grids; 62,187 primary-definition and 32,895 auxiliary-definition multilingual records; 59 cities (20 Europe / 20 Asia and North Africa / 19 Latin America). Main model: β = 0.054036, city-clustered SE = 0.129393, 95% CI [−0.205, 0.313], Pearson dispersion = 4.176396.

## 6. Data sources and attribution

- **OpenStreetMap** data © OpenStreetMap contributors, available under the [Open Database License (ODbL) 1.0](https://www.openstreetmap.org/copyright). Processed derivatives in this repository are shared under the same attribution requirement.
- **UNESCO World Heritage List** coordinates and property metadata © UNESCO World Heritage Centre, used under the [UNESCO WHC data terms](https://whc.unesco.org/en/list/).

## 7. License

- **Code** (R and Python scripts): MIT License — see `LICENSE`.
- **Processed datasets, tables, and figures**: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), with the OSM/ODbL attribution above preserved.

## 8. Citation

If you use this archive, please cite the manuscript (citation to be updated upon publication).
