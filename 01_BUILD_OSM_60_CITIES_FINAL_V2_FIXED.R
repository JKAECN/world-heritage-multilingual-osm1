# ==============================================================================
# 01_BUILD_OSM_60_CITIES_FINAL.R
#
# Multilingual Visibility and Urban Land Use in World Heritage Cities
#
# INPUT:
#   UNESCO_60_CITIES_MASTER.csv
#
# OUTPUT:
#   LAND_FINAL_RESULTS/FINAL_60cities_grid500m.csv
#
# DATA:
#   UNESCO coordinates are already merged into the master CSV.
#   OpenStreetMap data are downloaded through public Overpass API endpoints.
#
# REQUIRED R PACKAGES:
#   sf
#   jsonlite
#
# No DuckDB / Python / overturemaps / xml2 / readxl / stringdist required.
# ==============================================================================

rm(list = ls())
gc()

options(
  stringsAsFactors = FALSE,
  timeout = 900
)

# ------------------------------------------------------------------------------
# 1. Packages
# ------------------------------------------------------------------------------

required_packages <- c("sf", "jsonlite")

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0) {
  stop(
    paste0(
      "缺少R包：",
      paste(missing_packages, collapse = ", "),
      "\n请把这条报错发给我。"
    )
  )
}

library(sf)
library(jsonlite)

sf::sf_use_s2(TRUE)

# ------------------------------------------------------------------------------
# 2. Read 60-city UNESCO master
# ------------------------------------------------------------------------------

cat("\n请选择 UNESCO_60_CITIES_MASTER.csv：\n")

master_file <- file.choose()

cities <- read.csv(
  master_file,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8-BOM"
)

required_columns <- c(
  "city",
  "country",
  "local_language",
  "macro_region",
  "unesco_official_name",
  "longitude",
  "latitude"
)

missing_columns <- setdiff(
  required_columns,
  names(cities)
)

if (length(missing_columns) > 0) {
  stop(
    paste0(
      "主表缺少以下列：",
      paste(missing_columns, collapse = ", ")
    )
  )
}

cities$longitude <- as.numeric(cities$longitude)
cities$latitude <- as.numeric(cities$latitude)

cities <- cities[
  is.finite(cities$longitude) &
    is.finite(cities$latitude),
  ,
  drop = FALSE
]

cat("有效城市数：", nrow(cities), "\n")

# ------------------------------------------------------------------------------
# 3. Output folders
# ------------------------------------------------------------------------------

BASE_DIR <- dirname(master_file)

OUT_DIR <- file.path(
  BASE_DIR,
  "LAND_FINAL_RESULTS"
)

RAW_POI_DIR <- file.path(
  OUT_DIR,
  "01_raw_osm_poi"
)

RAW_LAND_DIR <- file.path(
  OUT_DIR,
  "02_raw_osm_landuse"
)

CITY_DIR <- file.path(
  OUT_DIR,
  "03_city_grid_data"
)

dir.create(
  OUT_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  RAW_POI_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  RAW_LAND_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  CITY_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)

# ------------------------------------------------------------------------------
# 4. Parameters
# ------------------------------------------------------------------------------

STUDY_RADIUS_KM <- 8

DOWNLOAD_RADIUS_KM <- 8.5

GRID_SIZE_M <- 500

REQUEST_PAUSE_SECONDS <- 3

OVERPASS_ENDPOINTS <- c(
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter"
)

# ------------------------------------------------------------------------------
# 5. Basic helpers
# ------------------------------------------------------------------------------

slugify <- function(x) {

  y <- iconv(
    x,
    from = "",
    to = "ASCII//TRANSLIT"
  )

  if (is.na(y)) {
    y <- x
  }

  y <- tolower(y)

  y <- gsub(
    "[^a-z0-9]+",
    "_",
    y
  )

  y <- gsub(
    "^_|_$",
    "",
    y
  )

  y
}

get_utm_epsg <- function(lon, lat) {

  zone <- floor(
    (lon + 180) / 6
  ) + 1

  if (lat >= 0) {
    32600 + zone
  } else {
    32700 + zone
  }
}

make_bbox <- function(lon, lat, radius_km) {

  lat_delta <- radius_km / 111.32

  lon_delta <- radius_km / (
    111.32 *
      cos(lat * pi / 180)
  )

  c(
    south = lat - lat_delta,
    west = lon - lon_delta,
    north = lat + lat_delta,
    east = lon + lon_delta
  )
}

get_tag <- function(tags, key) {

  if (
    is.null(tags) ||
    is.null(tags[[key]])
  ) {
    return("")
  }

  as.character(
    tags[[key]]
  )
}

# ------------------------------------------------------------------------------
# 6. Language-tag helpers
# ------------------------------------------------------------------------------

is_language_name_key <- function(key) {

  grepl(
    "^name:[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$",
    key
  )
}

parse_osm_language <- function(tags) {

  default_name <- get_tag(
    tags,
    "name"
  )

  if (default_name == "") {
    default_name <- NA_character_
  }

  keys <- names(tags)

  if (is.null(keys)) {
    keys <- character(0)
  }

  lang_keys <- keys[
    vapply(
      keys,
      is_language_name_key,
      logical(1)
    )
  ]

  lang_codes <- sub(
    "^name:",
    "",
    lang_keys
  )

  base_languages <- unique(
    tolower(
      sub(
        "-.*$",
        "",
        lang_codes
      )
    )
  )

  base_languages <- base_languages[
    !is.na(base_languages) &
      nzchar(base_languages)
  ]

  if (length(lang_keys) > 0) {

    language_values <- vapply(
      lang_keys,
      function(k) {
        as.character(
          tags[[k]]
        )
      },
      character(1)
    )

  } else {

    language_values <- character(0)
  }

  strict_multilingual <- (
    length(base_languages) >= 2
  )

  default_differs <- FALSE

  if (
    !is.na(default_name) &&
    length(language_values) > 0
  ) {

    default_differs <- any(
      trimws(language_values) !=
        trimws(default_name)
    )
  }

  primary_multilingual <- (
    strict_multilingual ||
      (
        length(base_languages) >= 1 &&
          default_differs
      )
  )

  int_name <- get_tag(
    tags,
    "int_name"
  )

  data.frame(
    default_name = default_name,
    n_explicit_languages = length(base_languages),
    language_tags = paste(
      sort(base_languages),
      collapse = "|"
    ),
    has_english = ("en" %in% base_languages),
    multilingual_primary = primary_multilingual,
    multilingual_strict = strict_multilingual,
    has_int_name = nzchar(int_name),
    stringsAsFactors = FALSE
  )
}

# ------------------------------------------------------------------------------
# 7. Visitor-oriented POI
# ------------------------------------------------------------------------------

is_visitor_poi <- function(tags) {

  tourism <- get_tag(
    tags,
    "tourism"
  )

  historic <- get_tag(
    tags,
    "historic"
  )

  amenity <- get_tag(
    tags,
    "amenity"
  )

  shop <- get_tag(
    tags,
    "shop"
  )

  leisure <- get_tag(
    tags,
    "leisure"
  )

  railway <- get_tag(
    tags,
    "railway"
  )

  public_transport <- get_tag(
    tags,
    "public_transport"
  )

  visitor_amenities <- c(
    "restaurant",
    "cafe",
    "bar",
    "pub",
    "food_court",
    "theatre",
    "arts_centre",
    "cinema",
    "marketplace",
    "ferry_terminal"
  )

  visitor_shops <- c(
    "souvenir",
    "gift",
    "travel_agency"
  )

  visitor_leisure <- c(
    "theme_park",
    "water_park",
    "marina"
  )

  (
    nzchar(tourism) ||
      nzchar(historic) ||
      amenity %in% visitor_amenities ||
      shop %in% visitor_shops ||
      leisure %in% visitor_leisure ||
      railway == "station" ||
      public_transport == "station"
  )
}

# ------------------------------------------------------------------------------
# 8. Overpass download
# ------------------------------------------------------------------------------

download_overpass <- function(
  query,
  output_file,
  max_tries = 3
) {

  if (
    file.exists(output_file) &&
    file.info(output_file)$size > 200
  ) {

    valid_existing <- tryCatch(
      {
        jsonlite::fromJSON(
          output_file,
          simplifyVector = FALSE
        )
        TRUE
      },
      error = function(e) FALSE
    )

    if (valid_existing) {
      return(TRUE)
    }
  }

  encoded_query <- utils::URLencode(
    query,
    reserved = TRUE
  )

  for (endpoint in OVERPASS_ENDPOINTS) {

    for (attempt in seq_len(max_tries)) {

      cat(
        "    ",
        endpoint,
        "  attempt ",
        attempt,
        "\n",
        sep = ""
      )

      request_url <- paste0(
        endpoint,
        "?data=",
        encoded_query
      )

      temp_file <- paste0(
        output_file,
        ".tmp"
      )

      ok <- tryCatch(
        {
          utils::download.file(
            url = request_url,
            destfile = temp_file,
            mode = "wb",
            quiet = TRUE,
            method = "libcurl"
          )
          TRUE
        },
        error = function(e) FALSE
      )

      if (
        ok &&
        file.exists(temp_file) &&
        file.info(temp_file)$size > 200
      ) {

        valid_json <- tryCatch(
          {
            jsonlite::fromJSON(
              temp_file,
              simplifyVector = FALSE
            )
            TRUE
          },
          error = function(e) FALSE
        )

        if (valid_json) {

          if (file.exists(output_file)) {
            file.remove(output_file)
          }

          file.rename(
            temp_file,
            output_file
          )

          Sys.sleep(
            REQUEST_PAUSE_SECONDS
          )

          return(TRUE)
        }
      }

      if (file.exists(temp_file)) {
        file.remove(temp_file)
      }

      Sys.sleep(6)
    }
  }

  FALSE
}

# ------------------------------------------------------------------------------
# 9. Overpass queries
# ------------------------------------------------------------------------------

make_poi_query <- function(bbox) {

  b <- paste(
    sprintf(
      "%.7f",
      bbox
    ),
    collapse = ","
  )

  paste0(
    "[out:json][timeout:180];(",

    "nwr[\"name\"][\"tourism\"](",
    b,
    ");",

    "nwr[\"name\"][\"amenity\"](",
    b,
    ");",

    "nwr[\"name\"][\"shop\"](",
    b,
    ");",

    "nwr[\"name\"][\"leisure\"](",
    b,
    ");",

    "nwr[\"name\"][\"historic\"](",
    b,
    ");",

    "nwr[\"name\"][\"office\"](",
    b,
    ");",

    "nwr[\"name\"][\"public_transport\"](",
    b,
    ");",

    "nwr[\"name\"][\"railway\"=\"station\"](",
    b,
    ");",

    ");out center tags;"
  )
}

make_land_query <- function(bbox) {

  b <- paste(
    sprintf(
      "%.7f",
      bbox
    ),
    collapse = ","
  )

  paste0(
    "[out:json][timeout:240];",
    "way[\"landuse\"](",
    b,
    ");",
    "out tags geom;"
  )
}

# ------------------------------------------------------------------------------
# 10. Read OSM POI
# ------------------------------------------------------------------------------

read_osm_poi <- function(json_file, city_name) {

  x <- jsonlite::fromJSON(
    json_file,
    simplifyVector = FALSE
  )

  elements <- x$elements

  if (
    is.null(elements) ||
    length(elements) == 0
  ) {
    return(
      data.frame()
    )
  }

  rows <- list()

  for (el in elements) {

    tags <- el$tags

    if (
      is.null(tags) ||
      is.null(tags$name)
    ) {
      next
    }

    lon <- el$lon
    lat <- el$lat

    if (
      (
        is.null(lon) ||
        is.null(lat)
      ) &&
      !is.null(el$center)
    ) {
      lon <- el$center$lon
      lat <- el$center$lat
    }

    if (
      is.null(lon) ||
      is.null(lat)
    ) {
      next
    }

    lang <- parse_osm_language(
      tags
    )

    rows[[length(rows) + 1]] <- data.frame(
      city = city_name,
      osm_type = as.character(el$type),
      osm_id = as.character(el$id),
      default_name = lang$default_name,
      n_explicit_languages = lang$n_explicit_languages,
      language_tags = lang$language_tags,
      has_english = lang$has_english,
      multilingual_primary = lang$multilingual_primary,
      multilingual_strict = lang$multilingual_strict,
      has_int_name = lang$has_int_name,
      visitor_poi = is_visitor_poi(tags),
      tourism = get_tag(tags, "tourism"),
      amenity = get_tag(tags, "amenity"),
      shop = get_tag(tags, "shop"),
      leisure = get_tag(tags, "leisure"),
      historic = get_tag(tags, "historic"),
      lon = as.numeric(lon),
      lat = as.numeric(lat),
      stringsAsFactors = FALSE
    )
  }

  if (length(rows) == 0) {
    return(
      data.frame()
    )
  }

  do.call(
    rbind,
    rows
  )
}

# ------------------------------------------------------------------------------
# 11. OSM landuse
# ------------------------------------------------------------------------------

classify_landuse <- function(value) {

  value <- tolower(
    ifelse(
      is.na(value),
      "",
      value
    )
  )

  out <- rep(
    "other",
    length(value)
  )

  out[
    value == "residential"
  ] <- "residential"

  out[
    value %in% c(
      "commercial",
      "retail"
    )
  ] <- "commercial_retail"

  out[
    value %in% c(
      "industrial",
      "garages",
      "warehouse"
    )
  ] <- "industrial"

  out[
    value %in% c(
      "institutional",
      "education",
      "civic_admin"
    )
  ] <- "institutional"

  out[
    value %in% c(
      "recreation_ground",
      "village_green"
    )
  ] <- "recreation_green"

  out[
    value %in% c(
      "forest",
      "grass",
      "meadow"
    )
  ] <- "green_natural"

  out[
    value %in% c(
      "farmland",
      "farmyard",
      "orchard",
      "vineyard",
      "plant_nursery",
      "allotments"
    )
  ] <- "agriculture"

  out[
    value %in% c(
      "railway",
      "port"
    )
  ] <- "transportation"

  out[
    value == "construction"
  ] <- "construction"

  out
}

way_to_polygon <- function(geometry) {

  if (
    is.null(geometry) ||
    length(geometry) < 3
  ) {
    return(NULL)
  }

  coords <- do.call(
    rbind,
    lapply(
      geometry,
      function(point) {
        c(
          lon = as.numeric(point$lon),
          lat = as.numeric(point$lat)
        )
      }
    )
  )

  if (
    is.null(coords) ||
    nrow(coords) < 3 ||
    any(!is.finite(coords))
  ) {
    return(NULL)
  }

  if (
    !all(
      coords[1, ] ==
        coords[nrow(coords), ]
    )
  ) {
    coords <- rbind(
      coords,
      coords[1, ]
    )
  }

  if (nrow(coords) < 4) {
    return(NULL)
  }

  tryCatch(
    sf::st_polygon(
      list(coords)
    ),
    error = function(e) NULL
  )
}

read_osm_landuse <- function(json_file) {

  x <- jsonlite::fromJSON(
    json_file,
    simplifyVector = FALSE
  )

  elements <- x$elements

  if (
    is.null(elements) ||
    length(elements) == 0
  ) {
    return(NULL)
  }

  polygons <- list()
  attributes <- list()

  for (el in elements) {

    tags <- el$tags

    if (
      is.null(tags) ||
      is.null(tags$landuse)
    ) {
      next
    }

    polygon <- way_to_polygon(
      el$geometry
    )

    if (is.null(polygon)) {
      next
    }

    polygons[[length(polygons) + 1]] <- polygon

    attributes[[length(attributes) + 1]] <- data.frame(
      osm_id = as.character(el$id),
      landuse = as.character(tags$landuse),
      land_group = classify_landuse(
        as.character(tags$landuse)
      ),
      stringsAsFactors = FALSE
    )
  }

  if (length(polygons) == 0) {
    return(NULL)
  }

  attribute_df <- do.call(
    rbind,
    attributes
  )

  geometry_sfc <- sf::st_sfc(
    polygons,
    crs = 4326
  )

  sf::st_sf(
    attribute_df,
    geometry = geometry_sfc
  )
}

# ------------------------------------------------------------------------------
# 12. Grid summaries
# ------------------------------------------------------------------------------

summarise_language_by_grid <- function(
  poi_grid,
  grid_ids
) {

  result <- data.frame(
    grid_id = grid_ids,
    n_named_poi = 0,
    n_language_tagged = 0,
    explicit_language_tag_coverage = NA_real_,
    n_multilingual_primary = 0,
    multilingual_visibility_primary = NA_real_,
    n_multilingual_strict = 0,
    multilingual_visibility_strict = NA_real_,
    n_english = 0,
    english_visibility = NA_real_,
    n_int_name = 0,
    international_name_visibility = NA_real_,
    n_visitor_poi = 0,
    visitor_poi_share = NA_real_,
    mean_explicit_languages = NA_real_,
    language_richness = 0,
    language_entropy = 0,
    stringsAsFactors = FALSE
  )

  if (
    is.null(poi_grid) ||
    nrow(poi_grid) == 0
  ) {
    return(result)
  }

  poi_df <- sf::st_drop_geometry(
    poi_grid
  )

  split_poi <- split(
    poi_df,
    poi_df$grid_id
  )

  for (gid in names(split_poi)) {

    z <- split_poi[[gid]]

    row_index <- match(
      gid,
      result$grid_id
    )

    if (is.na(row_index)) {
      next
    }

    result$n_named_poi[row_index] <- nrow(z)

    result$n_language_tagged[row_index] <- sum(
      z$n_explicit_languages > 0,
      na.rm = TRUE
    )

    result$explicit_language_tag_coverage[row_index] <- mean(
      z$n_explicit_languages > 0,
      na.rm = TRUE
    )

    result$n_multilingual_primary[row_index] <- sum(
      z$multilingual_primary,
      na.rm = TRUE
    )

    result$multilingual_visibility_primary[row_index] <- mean(
      z$multilingual_primary,
      na.rm = TRUE
    )

    result$n_multilingual_strict[row_index] <- sum(
      z$multilingual_strict,
      na.rm = TRUE
    )

    result$multilingual_visibility_strict[row_index] <- mean(
      z$multilingual_strict,
      na.rm = TRUE
    )

    result$n_english[row_index] <- sum(
      z$has_english,
      na.rm = TRUE
    )

    result$english_visibility[row_index] <- mean(
      z$has_english,
      na.rm = TRUE
    )

    result$n_int_name[row_index] <- sum(
      z$has_int_name,
      na.rm = TRUE
    )

    result$international_name_visibility[row_index] <- mean(
      z$has_int_name,
      na.rm = TRUE
    )

    result$n_visitor_poi[row_index] <- sum(
      z$visitor_poi,
      na.rm = TRUE
    )

    result$visitor_poi_share[row_index] <- mean(
      z$visitor_poi,
      na.rm = TRUE
    )

    result$mean_explicit_languages[row_index] <- mean(
      z$n_explicit_languages,
      na.rm = TRUE
    )

    language_vector <- character(0)

    nonempty_tags <- z$language_tags[
      !is.na(z$language_tags) &
        nzchar(z$language_tags)
    ]

    if (length(nonempty_tags) > 0) {

      language_vector <- unlist(
        strsplit(
          nonempty_tags,
          split = "\\|"
        )
      )

      language_vector <- language_vector[
        nzchar(language_vector)
      ]
    }

    if (length(language_vector) > 0) {

      language_counts <- table(
        language_vector
      )

      p <- as.numeric(
        language_counts
      ) / sum(
        language_counts
      )

      result$language_richness[row_index] <- length(
        language_counts
      )

      result$language_entropy[row_index] <- -sum(
        p * log(p)
      )
    }
  }

  result
}

LAND_GROUPS <- c(
  "residential",
  "commercial_retail",
  "industrial",
  "institutional",
  "recreation_green",
  "green_natural",
  "agriculture",
  "transportation",
  "construction",
  "other"
)

summarise_landuse_by_grid <- function(
  land_sf,
  grid
) {

  result <- data.frame(
    grid_id = grid$grid_id,
    stringsAsFactors = FALSE
  )

  for (g in LAND_GROUPS) {
    result[[paste0("land_", g)]] <- 0
  }

  result$landuse_mapped_coverage <- 0

  if (
    is.null(land_sf) ||
    nrow(land_sf) == 0
  ) {
    return(result)
  }

  land_sf <- suppressWarnings(
    sf::st_make_valid(
      land_sf
    )
  )

  land_int <- suppressWarnings(
    sf::st_intersection(
      land_sf[
        ,
        "land_group",
        drop = FALSE
      ],
      grid[
        ,
        c(
          "grid_id",
          "grid_area_m2"
        ),
        drop = FALSE
      ]
    )
  )

  if (nrow(land_int) == 0) {
    return(result)
  }

  land_int$piece_area_m2 <- as.numeric(
    sf::st_area(
      land_int
    )
  )

  land_df <- sf::st_drop_geometry(
    land_int
  )

  split_grid <- split(
    land_df,
    land_df$grid_id
  )

  for (gid in names(split_grid)) {

    z <- split_grid[[gid]]

    row_index <- match(
      gid,
      result$grid_id
    )

    if (is.na(row_index)) {
      next
    }

    grid_area <- z$grid_area_m2[1]

    for (g in LAND_GROUPS) {

      area_sum <- sum(
        z$piece_area_m2[
          z$land_group == g
        ],
        na.rm = TRUE
      )

      result[
        row_index,
        paste0("land_", g)
      ] <- min(
        area_sum / grid_area,
        1
      )
    }

    result$landuse_mapped_coverage[row_index] <- min(
      sum(
        z$piece_area_m2,
        na.rm = TRUE
      ) / grid_area,
      1
    )
  }

  result
}

# ------------------------------------------------------------------------------
# 13. City loop
# ------------------------------------------------------------------------------

all_city_results <- list()

error_log <- data.frame(
  city = character(0),
  error = character(0),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(cities))) {

  city_name <- cities$city[i]

  city_slug <- slugify(
    city_name
  )

  cat(
    "\n============================================================\n",
    i,
    "/",
    nrow(cities),
    "  ",
    city_name,
    "\n",
    "============================================================\n",
    sep = ""
  )

  city_csv <- file.path(
    CITY_DIR,
    paste0(
      city_slug,
      "_grid500m.csv"
    )
  )

  if (file.exists(city_csv)) {

    cat(
      "已有结果，跳过该城市。\n"
    )

    old_result <- read.csv(
      city_csv,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )

    all_city_results[[length(all_city_results) + 1]] <- old_result

    next
  }

  city_result <- tryCatch(
    {

      lon <- cities$longitude[i]
      lat <- cities$latitude[i]

      epsg <- get_utm_epsg(
        lon,
        lat
      )

      bbox <- make_bbox(
        lon,
        lat,
        DOWNLOAD_RADIUS_KM
      )

      # POI download
      poi_json <- file.path(
        RAW_POI_DIR,
        paste0(
          city_slug,
          "_poi.json"
        )
      )

      cat(
        "下载OSM语言景观POI...\n"
      )

      poi_ok <- download_overpass(
        make_poi_query(bbox),
        poi_json
      )

      if (!poi_ok) {
        stop(
          "POI下载失败"
        )
      }

      # Landuse download
      land_json <- file.path(
        RAW_LAND_DIR,
        paste0(
          city_slug,
          "_landuse.json"
        )
      )

      cat(
        "下载OSM landuse...\n"
      )

      land_ok <- download_overpass(
        make_land_query(bbox),
        land_json
      )

      if (!land_ok) {
        stop(
          "landuse下载失败"
        )
      }

      # Study area
      center_wgs <- sf::st_sfc(
        sf::st_point(
          c(lon, lat)
        ),
        crs = 4326
      )

      center_utm <- sf::st_transform(
        center_wgs,
        crs = epsg
      )

      study_circle <- sf::st_buffer(
        center_utm,
        dist = STUDY_RADIUS_KM * 1000
      )

      grid <- sf::st_make_grid(
        study_circle,
        cellsize = GRID_SIZE_M,
        square = TRUE
      )

      grid <- sf::st_as_sf(
        grid
      )

      grid <- suppressWarnings(
        sf::st_intersection(
          grid,
          study_circle
        )
      )

      grid$grid_id <- sprintf(
        "%s_%04d",
        city_slug,
        seq_len(nrow(grid))
      )

      grid$grid_area_m2 <- as.numeric(
        sf::st_area(
          grid
        )
      )

      # Language data
      poi <- read_osm_poi(
        poi_json,
        city_name
      )

      cat(
        "有效有名称POI：",
        nrow(poi),
        "\n"
      )

      if (nrow(poi) == 0) {
        stop(
          "没有有效POI"
        )
      }

      poi_sf <- sf::st_as_sf(
        poi,
        coords = c(
          "lon",
          "lat"
        ),
        crs = 4326,
        remove = FALSE
      )

      poi_sf <- sf::st_transform(
        poi_sf,
        crs = epsg
      )

      poi_sf <- sf::st_filter(
        poi_sf,
        study_circle
      )

      poi_grid <- sf::st_join(
        poi_sf,
        grid[
          ,
          "grid_id",
          drop = FALSE
        ],
        left = FALSE
      )

      language_grid <- summarise_language_by_grid(
        poi_grid,
        grid$grid_id
      )

      # Landuse data
      land_sf <- read_osm_landuse(
        land_json
      )

      if (!is.null(land_sf)) {

        land_sf <- sf::st_transform(
          land_sf,
          crs = epsg
        )

        land_sf <- sf::st_filter(
          land_sf,
          study_circle
        )

        cat(
          "有效landuse polygon：",
          nrow(land_sf),
          "\n"
        )

      } else {

        cat(
          "有效landuse polygon：0\n"
        )
      }

      land_grid <- summarise_landuse_by_grid(
        land_sf,
        grid
      )

      # Merge grid attributes
      grid_df <- sf::st_drop_geometry(
        grid
      )

      result <- merge(
        grid_df,
        language_grid,
        by = "grid_id",
        all.x = TRUE,
        sort = FALSE
      )

      result <- merge(
        result,
        land_grid,
        by = "grid_id",
        all.x = TRUE,
        sort = FALSE
      )

      # Distance to UNESCO representative coordinate
      grid_centroids <- suppressWarnings(
        sf::st_centroid(
          grid
        )
      )

      distance_df <- data.frame(
        grid_id = grid$grid_id,
        heritage_distance_m = as.numeric(
          sf::st_distance(
            grid_centroids,
            center_utm
          )
        ),
        stringsAsFactors = FALSE
      )

      result <- merge(
        result,
        distance_df,
        by = "grid_id",
        all.x = TRUE,
        sort = FALSE
      )

      # City metadata
      result$city <- city_name
      result$country <- cities$country[i]
      result$macro_region <- cities$macro_region[i]
      result$local_language <- cities$local_language[i]
      result$unesco_property <- cities$unesco_official_name[i]
      result$heritage_longitude <- lon
      result$heritage_latitude <- lat
      result$data_access_date <- as.character(
        Sys.Date()
      )

      result$heritage_distance_km <- (
        result$heritage_distance_m / 1000
      )

      result$poi_density_km2 <- (
        result$n_named_poi /
          (
            result$grid_area_m2 / 1e6
          )
      )

      result$visitor_poi_density_km2 <- (
        result$n_visitor_poi /
          (
            result$grid_area_m2 / 1e6
          )
      )

      write.csv(
        result,
        city_csv,
        row.names = FALSE,
        fileEncoding = "UTF-8"
      )

      cat(
        "完成，网格数：",
        nrow(result),
        "\n"
      )

      result
    },
    error = function(e) {

      cat(
        "失败：",
        conditionMessage(e),
        "\n"
      )

      error_log <<- rbind(
        error_log,
        data.frame(
          city = city_name,
          error = conditionMessage(e),
          stringsAsFactors = FALSE
        )
      )

      NULL
    }
  )

  if (!is.null(city_result)) {

    all_city_results[[length(all_city_results) + 1]] <- city_result
  }

  write.csv(
    error_log,
    file.path(
      OUT_DIR,
      "ERROR_LOG.csv"
    ),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )

  gc()
}

# ------------------------------------------------------------------------------
# 14. Final merged database
# ------------------------------------------------------------------------------

if (length(all_city_results) == 0) {
  stop(
    "没有任何城市成功完成，请查看 ERROR_LOG.csv。"
  )
}

final_data <- do.call(
  rbind,
  all_city_results
)

FINAL_FILE <- file.path(
  OUT_DIR,
  "FINAL_60cities_grid500m.csv"
)

write.csv(
  final_data,
  FINAL_FILE,
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

# ------------------------------------------------------------------------------
# 15. City-level quality summary
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
  final_data$city
)

quality_list <- vector(
  "list",
  length(city_names)
)

for (j in seq_along(city_names)) {

  cname <- city_names[j]

  z <- final_data[
    final_data$city == cname,
    ,
    drop = FALSE
  ]

  quality_list[[j]] <- data.frame(
    city = cname,
    country = z$country[1],
    macro_region = z$macro_region[1],
    n_grids = nrow(z),
    n_named_poi = sum(
      z$n_named_poi,
      na.rm = TRUE
    ),
    explicit_language_tag_coverage = safe_weighted_mean(
      z$explicit_language_tag_coverage,
      z$n_named_poi
    ),
    multilingual_visibility_primary = safe_weighted_mean(
      z$multilingual_visibility_primary,
      z$n_named_poi
    ),
    multilingual_visibility_strict = safe_weighted_mean(
      z$multilingual_visibility_strict,
      z$n_named_poi
    ),
    english_visibility = safe_weighted_mean(
      z$english_visibility,
      z$n_named_poi
    ),
    mean_landuse_mapped_coverage = mean(
      z$landuse_mapped_coverage,
      na.rm = TRUE
    ),
    stringsAsFactors = FALSE
  )
}

city_quality <- do.call(
  rbind,
  quality_list
)

write.csv(
  city_quality,
  file.path(
    OUT_DIR,
    "CITY_DATA_QUALITY.csv"
  ),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

# ------------------------------------------------------------------------------
# 16. Save data objects
# ------------------------------------------------------------------------------

save(
  final_data,
  city_quality,
  cities,
  file = file.path(
    OUT_DIR,
    "FINAL_60cities_DATA.RData"
  )
)

writeLines(
  c(
    paste0(
      "Data access date: ",
      Sys.Date()
    ),
    "UNESCO coordinates: pre-matched from UNESCO World Heritage List XLSX.",
    "Digital linguistic landscape: OpenStreetMap via Overpass API.",
    "Language tags: name:<language> and int_name.",
    "Urban land use: OSM landuse=* closed-way polygons.",
    "Study radius: 8 km around UNESCO representative coordinate.",
    "Grid: 500 m.",
    "Primary multilingual measure: default name plus a distinct explicit language name, or >=2 explicit language tags.",
    "Strict multilingual measure: >=2 explicit language tags.",
    "landuse_mapped_coverage is a data-quality diagnostic.",
    "OpenStreetMap data are licensed under ODbL."
  ),
  file.path(
    OUT_DIR,
    "DATA_METHOD_NOTE.txt"
  )
)

cat(
  "\n============================================================\n",
  "全部运行结束。\n",
  "成功城市数：",
  length(unique(final_data$city)),
  "\n",
  "总网格数：",
  nrow(final_data),
  "\n",
  "最终数据库：\n",
  FINAL_FILE,
  "\n",
  "============================================================\n",
  sep = ""
)
