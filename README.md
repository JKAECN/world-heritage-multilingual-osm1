# Multilingual Digital Visibility of World Heritage in OpenStreetMap

Replication archive for the manuscript:

> **Cross-City Multilingual Digital Visibility of World Heritage in OpenStreetMap: A 59-City Grid-Based Assessment**
> (revised manuscript, 2026)

This repository contains the analysis code, processed datasets, validation records, and figures needed to reproduce every number, table, and figure reported in the revised manuscript and the response to reviewers.

---

## 1. Study design in brief

- **Scope**: 59 World Heritage cities in 36 countries (Europe 20, Asia/MENA 20, Latin America 19).
- **Spatial unit**: 500 m × 500 m projected grid cells within an 8 km window around each UNESCO property centroid; 50,506 cells in total.
- **Primary analytical sample**: the 15,020 cells with ≥5 function-filtered named OSM features (the eligibility rule reported in Section 2.4 of the manuscript).
- **Outcome**: multilingual digital visibility — the share of named OSM features whose primary name carries more than one script (primary definition), with rule-based sensitivity recodings (strict auxiliary-name and lenient token-level variants).
- **Data snapshot**: OpenStreetMap via the Overpass API on **2026-10-17**; UNESCO World Heritage List coordinates (1,273 properties, 2026 DataHub release).

## 2. Reproduction workflow

All steps are indexed, with SHA-256 hashes and byte sizes, in **`manifest.yaml`** (287 files). Verify any file with:

```bash
sha256sum <file>   # compare against the "sha256" field in manifest.yaml
```

| Step | Script | Inputs → Outputs |
|---|---|---|
| 1 | `01_BUILD_OSM_60_CITIES_FINAL_V2_FIXED.R` | `UNESCO_60_CITIES_MASTER.csv` + Overpass raw extracts → `LAND_FINAL_RESULTS/FINAL_60cities_grid500m.csv`, per-city grids (`LAND_FINAL_RESULTS/03_city_grid_data/`), `LAND_FINAL_RESULTS/CITY_DATA_QUALITY.csv` |
| 2 | `02_ANALYZE_FINAL_DATA_V2_FIXED.R` | step-1 outputs → `LAND_FINAL_RESULTS/ANALYSIS_RESULTS/` |
| 3 | `LAND_PAPER/artifacts/scripts/land_analysis_full.py` | analysis sample → `LAND_PAPER/artifacts/` (`analysis_sample.csv`, model tables, `pred_distance_gradient.csv`) |
| 4 | `LAND_PAPER/reanalysis/run_reanalysis.py` | analysis sample → `LAND_PAPER/reanalysis/` |
| 5 | `validation_audit.py` | coding sheets → `validation_audit_worksheet.csv`, `audit_summary.json` |

**Raw Overpass extracts (~535 MB) are not redistributed** (ODbL share-alike; re-downloadable with the archived queries at the recorded snapshot date). All downstream artefacts are derivable from step 1 onward.

**Grid reconstruction check.** Given only the per-city UTM zone formula (`zone = floor((lon+180)/6)+1`; EPSG 32600+zone north / 32700+zone south), the UNESCO coordinates in `UNESCO_60_CITIES_MASTER.csv`, and the grid indices in `grid_v7_metrics.csv`, the heritage distance of every interior cell can be reconstructed with a maximum absolute error of **3.4 × 10⁻¹⁰ m** across all 59 cities.

## 3. Repository layout

```
manifest.yaml                      SHA-256 / byte-size index of every analysis file (271 entries)
01_BUILD_OSM_60_CITIES_FINAL_V2_FIXED.R    step-1 build script
02_ANALYZE_FINAL_DATA_V2_FIXED.R           step-2 analysis script
UNESCO_60_CITIES_MASTER.csv        city list, UNESCO coordinates, macro-region
Coding_Manual.docx                 double-blind validation coding manual
Coder1_Blind_coded.xlsx            coder-1 blind validation sheet
validation_audit.py                step-5 audit script
validation_audit_worksheet.csv     360-cell audit worksheet
audit_summary.json                 audit summary (agreement statistics)

LAND_FINAL_RESULTS/
  FINAL_60cities_grid500m.csv      authoritative grid-level dataset (50,506 cells; 59 cities)
  CITY_DATA_QUALITY.csv            per-city data-quality indicators
  ERROR_LOG.csv                    exclusion log: exactly one row (Puebla, land-use extract failed),
                                   cross-checked by build_reconciliation_v7.py
  03_city_grid_data/               per-city grid extracts

LAND_PAPER/
  artifacts/analysis_sample.csv    primary sample extract (15,020 cells)
  artifacts/pred_distance_gradient.csv        (see provenance note below)
  reanalysis_v7/                   re-analysis tables used in the revision
  reanalysis/bootstrap_cache.npz   (see provenance note below)

validation/
  Land_Distance_Band_Support_Verified.csv
  Land_59_City_Support_Verified.csv
  Land_Distance_Verification_Report.json

figures/                           the four manuscript figures as submitted
  Figure1A_sample_map.png  Figure1B_workflow.png
  Figure2_distance_bands.png  Figure3_city_maps.png
```

## 4. Provenance-retained files

`pred_distance_gradient.csv`, `gradient_contrast_boot_v7.csv`, and `bootstrap_cache.npz` were generated under a bootstrap prediction pipeline that was **retired during revision** (see Section 4.5 of the manuscript). They do not reconcile with the frozen banded counts, are not used by any reported result, and are retained solely for audit traceability.

## 5. Data sources and attribution

- **OpenStreetMap** data © OpenStreetMap contributors, available under the [Open Database License (ODbL) 1.0](https://www.openstreetmap.org/copyright). Processed derivatives in this repository are shared under the same attribution requirement.
- **UNESCO World Heritage List** coordinates and property metadata © UNESCO World Heritage Centre, used under the [UNESCO WHC data terms](https://whc.unesco.org/en/list/).

## 6. License

- **Code** (R and Python scripts): MIT License — see `LICENSE`.
- **Processed datasets, tables, and figures**: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), with the OSM/ODbL attribution above preserved.

## 7. Citation

If you use this archive, please cite the manuscript (citation to be updated upon publication).
