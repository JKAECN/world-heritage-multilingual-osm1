# ==============================================================================
# 02_ANALYZE_FINAL_DATA.R
#
# INPUT:
#   LAND_FINAL_RESULTS/FINAL_60cities_grid500m.csv
#
# No additional package is required for the core models.
# ==============================================================================

rm(list = ls())
gc()

options(
  stringsAsFactors = FALSE
)

cat("\n请选择 FINAL_60cities_grid500m.csv：\n")

data_file <- file.choose()

d0 <- read.csv(
  data_file,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8"
)

OUT_DIR <- file.path(
  dirname(data_file),
  "ANALYSIS_RESULTS"
)

dir.create(
  OUT_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)

required_columns <- c(
  "city",
  "country",
  "macro_region",
  "grid_id",
  "n_named_poi",
  "n_multilingual_primary",
  "multilingual_visibility_primary",
  "n_multilingual_strict",
  "multilingual_visibility_strict",
  "n_english",
  "english_visibility",
  "language_richness",
  "language_entropy",
  "n_visitor_poi",
  "visitor_poi_density_km2",
  "poi_density_km2",
  "heritage_distance_km",
  "land_commercial_retail",
  "land_residential",
  "land_recreation_green",
  "land_institutional",
  "land_transportation",
  "landuse_mapped_coverage"
)

missing_columns <- setdiff(
  required_columns,
  names(d0)
)

if (length(missing_columns) > 0) {
  stop(
    paste0(
      "最终数据缺少变量：",
      paste(missing_columns, collapse = ", ")
    )
  )
}

# ------------------------------------------------------------------------------
# 1. Main analysis sample
# ------------------------------------------------------------------------------

d <- d0[
  is.finite(d0$n_named_poi) &
    d0$n_named_poi >= 5,
  ,
  drop = FALSE
]

cat(
  "全部网格：",
  nrow(d0),
  "\n"
)

cat(
  "主分析网格（至少5个named POI）：",
  nrow(d),
  "\n"
)

cat(
  "城市数：",
  length(
    unique(d$city)
  ),
  "\n"
)

if (nrow(d) == 0) {
  stop(
    "没有满足 n_named_poi >= 5 的网格。"
  )
}

# ------------------------------------------------------------------------------
# 2. Descriptive summaries
# ------------------------------------------------------------------------------

safe_weighted_mean <- function(x, w) {

  ok <- is.finite(x) &
    is.finite(w) &
    w > 0

  if (!any(ok)) {
    return(NA_real_)
  }

  weighted.mean(
    x[ok],
    w[ok]
  )
}

city_names <- unique(
  d$city
)

city_summary_list <- vector(
  "list",
  length(city_names)
)

for (i in seq_along(city_names)) {

  cname <- city_names[i]

  z <- d[
    d$city == cname,
    ,
    drop = FALSE
  ]

  city_summary_list[[i]] <- data.frame(
    city = cname,
    country = z$country[1],
    macro_region = z$macro_region[1],
    n_grids = nrow(z),
    n_named_poi = sum(
      z$n_named_poi,
      na.rm = TRUE
    ),
    multilingual_primary = safe_weighted_mean(
      z$multilingual_visibility_primary,
      z$n_named_poi
    ),
    multilingual_strict = safe_weighted_mean(
      z$multilingual_visibility_strict,
      z$n_named_poi
    ),
    english_visibility = safe_weighted_mean(
      z$english_visibility,
      z$n_named_poi
    ),
    mean_language_richness = mean(
      z$language_richness,
      na.rm = TRUE
    ),
    mean_language_entropy = mean(
      z$language_entropy,
      na.rm = TRUE
    ),
    visitor_poi_density = mean(
      z$visitor_poi_density_km2,
      na.rm = TRUE
    ),
    mean_landuse_coverage = mean(
      z$landuse_mapped_coverage,
      na.rm = TRUE
    ),
    stringsAsFactors = FALSE
  )
}

city_summary <- do.call(
  rbind,
  city_summary_list
)

write.csv(
  city_summary,
  file.path(
    OUT_DIR,
    "TABLE_city_summary.csv"
  ),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

# ------------------------------------------------------------------------------
# 3. Distance bands
# ------------------------------------------------------------------------------

d$distance_band <- cut(
  d$heritage_distance_km,
  breaks = c(
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    Inf
  ),
  right = FALSE,
  labels = c(
    "0-1",
    "1-2",
    "2-3",
    "3-4",
    "4-5",
    "5-6",
    "6-7",
    "7+"
  )
)

distance_levels <- levels(
  d$distance_band
)

distance_summary_list <- list()

for (band in distance_levels) {

  z <- d[
    d$distance_band == band,
    ,
    drop = FALSE
  ]

  if (nrow(z) == 0) {
    next
  }

  distance_summary_list[[length(distance_summary_list) + 1]] <- data.frame(
    distance_band = band,
    n_grids = nrow(z),
    multilingual_primary = safe_weighted_mean(
      z$multilingual_visibility_primary,
      z$n_named_poi
    ),
    multilingual_strict = safe_weighted_mean(
      z$multilingual_visibility_strict,
      z$n_named_poi
    ),
    english_visibility = safe_weighted_mean(
      z$english_visibility,
      z$n_named_poi
    ),
    visitor_poi_density = mean(
      z$visitor_poi_density_km2,
      na.rm = TRUE
    ),
    stringsAsFactors = FALSE
  )
}

distance_summary <- do.call(
  rbind,
  distance_summary_list
)

write.csv(
  distance_summary,
  file.path(
    OUT_DIR,
    "TABLE_distance_gradient.csv"
  ),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

# ------------------------------------------------------------------------------
# 4. Main model
#
# Outcome:
#   multilingual-primary POIs / named POIs
#
# City fixed effects absorb stable city-level differences.
# Heritage distance is nonlinear through natural splines.
# ------------------------------------------------------------------------------

d$primary_failure <- (
  d$n_named_poi -
    d$n_multilingual_primary
)

main_model <- glm(
  cbind(
    n_multilingual_primary,
    primary_failure
  ) ~
    log1p(
      visitor_poi_density_km2
    ) +
    land_commercial_retail +
    land_residential +
    land_recreation_green +
    land_institutional +
    land_transportation +
    log1p(
      poi_density_km2
    ) +
    splines::ns(
      heritage_distance_km,
      df = 4
    ) +
    factor(city),
  family = quasibinomial(),
  data = d
)

capture.output(
  summary(main_model),
  file = file.path(
    OUT_DIR,
    "MODEL_1_main_multilingual_primary.txt"
  )
)

# ------------------------------------------------------------------------------
# 5. Visitor intensity x commercial/retail land-use interaction
# ------------------------------------------------------------------------------

interaction_model <- glm(
  cbind(
    n_multilingual_primary,
    primary_failure
  ) ~
    log1p(
      visitor_poi_density_km2
    ) *
    land_commercial_retail +
    land_residential +
    land_recreation_green +
    land_institutional +
    land_transportation +
    log1p(
      poi_density_km2
    ) +
    splines::ns(
      heritage_distance_km,
      df = 4
    ) +
    factor(city),
  family = quasibinomial(),
  data = d
)

capture.output(
  summary(interaction_model),
  file = file.path(
    OUT_DIR,
    "MODEL_2_visitor_x_commercial.txt"
  )
)

# ------------------------------------------------------------------------------
# 6. Strict multilingual definition
# ------------------------------------------------------------------------------

d$strict_failure <- (
  d$n_named_poi -
    d$n_multilingual_strict
)

strict_model <- glm(
  cbind(
    n_multilingual_strict,
    strict_failure
  ) ~
    log1p(
      visitor_poi_density_km2
    ) +
    land_commercial_retail +
    land_residential +
    land_recreation_green +
    land_institutional +
    land_transportation +
    log1p(
      poi_density_km2
    ) +
    splines::ns(
      heritage_distance_km,
      df = 4
    ) +
    factor(city),
  family = quasibinomial(),
  data = d
)

capture.output(
  summary(strict_model),
  file = file.path(
    OUT_DIR,
    "MODEL_3_strict_multilingual_robustness.txt"
  )
)

# ------------------------------------------------------------------------------
# 7. English visibility
# ------------------------------------------------------------------------------

d$english_failure <- (
  d$n_named_poi -
    d$n_english
)

english_model <- glm(
  cbind(
    n_english,
    english_failure
  ) ~
    log1p(
      visitor_poi_density_km2
    ) +
    land_commercial_retail +
    land_residential +
    land_recreation_green +
    land_institutional +
    land_transportation +
    log1p(
      poi_density_km2
    ) +
    splines::ns(
      heritage_distance_km,
      df = 4
    ) +
    factor(city),
  family = quasibinomial(),
  data = d
)

capture.output(
  summary(english_model),
  file = file.path(
    OUT_DIR,
    "MODEL_4_english_visibility.txt"
  )
)

# ------------------------------------------------------------------------------
# 8. Multilingual service-tourism mismatch
# ------------------------------------------------------------------------------

z_score_safe <- function(x) {

  m <- mean(
    x,
    na.rm = TRUE
  )

  s <- sd(
    x,
    na.rm = TRUE
  )

  if (
    !is.finite(s) ||
    s == 0
  ) {
    return(
      rep(
        0,
        length(x)
      )
    )
  }

  (
    x - m
  ) / s
}

mismatch_cities <- unique(
  d$city
)

mismatch_list <- vector(
  "list",
  length(mismatch_cities)
)

for (i in seq_along(mismatch_cities)) {

  cname <- mismatch_cities[i]

  z <- d[
    d$city == cname,
    ,
    drop = FALSE
  ]

  z$z_visitor_intensity <- z_score_safe(
    log1p(
      z$visitor_poi_density_km2
    )
  )

  z$z_multilingual_visibility <- z_score_safe(
    z$multilingual_visibility_primary
  )

  z$mismatch_index <- (
    z$z_visitor_intensity -
      z$z_multilingual_visibility
  )

  mismatch_list[[i]] <- z
}

mismatch_data <- do.call(
  rbind,
  mismatch_list
)

write.csv(
  mismatch_data,
  file.path(
    OUT_DIR,
    "GRID_multilingual_service_tourism_mismatch.csv"
  ),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

cutoff_90 <- quantile(
  mismatch_data$mismatch_index,
  probs = 0.90,
  na.rm = TRUE
)

high_gap <- mismatch_data[
  is.finite(
    mismatch_data$mismatch_index
  ) &
    mismatch_data$mismatch_index >= cutoff_90,
  ,
  drop = FALSE
]

write.csv(
  high_gap,
  file.path(
    OUT_DIR,
    "GRID_top10pct_language_service_gap.csv"
  ),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

# ------------------------------------------------------------------------------
# 9. Sensitivity: minimum 10 and 20 named POIs per grid
# ------------------------------------------------------------------------------

run_sensitivity <- function(
  source_data,
  minimum_poi
) {

  z <- source_data[
    is.finite(
      source_data$n_named_poi
    ) &
      source_data$n_named_poi >= minimum_poi,
    ,
    drop = FALSE
  ]

  if (nrow(z) == 0) {
    return(NULL)
  }

  z$failure <- (
    z$n_named_poi -
      z$n_multilingual_primary
  )

  model <- glm(
    cbind(
      n_multilingual_primary,
      failure
    ) ~
      log1p(
        visitor_poi_density_km2
      ) +
      land_commercial_retail +
      land_residential +
      land_recreation_green +
      land_institutional +
      land_transportation +
      log1p(
        poi_density_km2
      ) +
      splines::ns(
        heritage_distance_km,
        df = 4
      ) +
      factor(city),
    family = quasibinomial(),
    data = z
  )

  capture.output(
    summary(model),
    file = file.path(
      OUT_DIR,
      paste0(
        "SENSITIVITY_min_named_POI_",
        minimum_poi,
        ".txt"
      )
    )
  )

  model
}

sensitivity_10 <- run_sensitivity(
  d0,
  10
)

sensitivity_20 <- run_sensitivity(
  d0,
  20
)

# ------------------------------------------------------------------------------
# 10. Save objects
# ------------------------------------------------------------------------------

save(
  d0,
  d,
  city_summary,
  distance_summary,
  main_model,
  interaction_model,
  strict_model,
  english_model,
  mismatch_data,
  file = file.path(
    OUT_DIR,
    "LAND_ANALYSIS_OBJECTS.RData"
  )
)

cat(
  "\n分析完成。\n",
  "结果目录：\n",
  OUT_DIR,
  "\n",
  sep = ""
)

