# Habitat Accounting (HA) cover classification for mini snorkel microhabitat units
#
# Collapses the individual cover percentages recorded for each microhabitat unit
# into ONE cover variable, following the HA qualifying criterion for tributary
# rearing habitat: cover features (HSI >= 0.5) must together make up >= 20% of
# the area (Appendix F, Habitat Accounting Protocols, section 2.1.3.5; the cover
# feature types are listed in its Table 28).
#
# Usage (from an Rmd or script):
#   source(here::here("mini-snorkel-analysis", "analysis", "ha_cover.R"))
#   units <- classify_ha_cover(units)                              # defaults
#   units <- classify_ha_cover(units, threshold = 30)              # different %
#   units <- classify_ha_cover(units, use = setdiff(ha_cover_map$ha_category, "boulder"))
#   units <- classify_ha_cover(units, method = "max")              # overlap-safe
#
# Output columns added to `data`:
#   cover      0/1: combined cover >= threshold
#   cover_pct  combined cover (%), capped at `cap` (continuous version of `cover`)
#   (optionally) ha_<category>_pct: percent contributed by each HA category

# ---- Mapping from HA cover categories to mini snorkel columns ----------------
#
# One row per (HA category, data column). A category can use more than one
# column (overhanging vegetation is recorded in two overhead classes). Edit this
# table, or pass your own as `map`, to change which columns count as cover.
#
# HA cover categories with NO matching mini snorkel column (not measured):
#   grass/herbaceous; willow and other riparian vegetation (overhanging
#   vegetation is the closest measured proxy).
# Boulder and cobble are both kept in the default definition (project decision),
# even though they are recorded as substrate columns in the survey. HA lists
# boulder as a cover category. The State Water Board's summary of Table 28
# excludes cobble < 12 in, but the VA accounting documents include cobble as
# cover, which is the choice made here. To drop either:
#   classify_ha_cover(data, use = setdiff(ha_cover_map$ha_category, "cobble"))
#   classify_ha_cover(data, use = setdiff(ha_cover_map$ha_category, c("boulder", "cobble")))
ha_cover_map <- data.frame(
  ha_category = c("woody_debris",
                  "root_wad_logjam_large_wood",
                  "aquatic_vegetation",
                  "undercut_bank",
                  "overhanging_vegetation",
                  "overhanging_vegetation",
                  "boulder",
                  "cobble"),
  column      = c("percent_small_woody_cover_inchannel",
                  "percent_large_woody_cover_inchannel",
                  "percent_submerged_aquatic_veg_inchannel",
                  "percent_undercut_bank",
                  "percent_cover_half_meter_overhead",
                  "percent_cover_more_than_half_meter_overhead",
                  "percent_boulder_substrate",
                  "percent_cobble_substrate"),
  stringsAsFactors = FALSE
)

#' Classify microhabitat units as having / not having HA cover
#'
#' @param data      data frame with the percent-cover columns named in `map`
#' @param threshold combined cover (%) at or above which `cover` = 1 (HA uses 20)
#' @param map       data frame with columns `ha_category` and `column`
#' @param use       HA categories to include (default: all categories in `map`)
#' @param method    how categories are combined into total cover:
#'                  "sum" adds them (assumes categories do not overlap spatially;
#'                  an upper bound), "max" takes the largest single category
#'                  (assumes full overlap; a lower bound)
#' @param cap       maximum percent for a column group / the total (default 100)
#' @param keep_categories add one `ha_<category>_pct` column per category
#'
#' Missing values: if any column used is NA the unit gets NA for `cover` and
#' `cover_pct` (units are not silently treated as having no cover).
#'
#' Percent within a category is the sum of its columns (e.g. both overhead
#' classes), capped at `cap`. The comparison is `>=` threshold, matching the HA
#' wording (">= 20%").
classify_ha_cover <- function(data,
                              threshold = 20,
                              map = ha_cover_map,
                              use = unique(map$ha_category),
                              method = c("sum", "max"),
                              cap = 100,
                              keep_categories = FALSE) {
  method <- match.arg(method)

  unknown <- setdiff(use, map$ha_category)
  if (length(unknown) > 0) {
    stop("Unknown HA categories in `use`: ", paste(unknown, collapse = ", "),
         ". Available: ", paste(unique(map$ha_category), collapse = ", "))
  }
  map <- map[map$ha_category %in% use, , drop = FALSE]
  if (nrow(map) == 0) stop("No HA categories selected.")

  missing_cols <- setdiff(map$column, names(data))
  if (length(missing_cols) > 0) {
    stop("Columns not found in `data`: ", paste(missing_cols, collapse = ", "))
  }

  categories <- unique(map$ha_category)

  # percent per HA category (sum of its columns, capped); NA propagates
  cat_pct <- do.call(cbind, lapply(categories, function(cat) {
    cols <- map$column[map$ha_category == cat]
    pmin(rowSums(as.matrix(data[, cols, drop = FALSE])), cap)
  }))
  colnames(cat_pct) <- categories

  total <- if (method == "sum") rowSums(cat_pct) else apply(cat_pct, 1, max)
  total <- pmin(total, cap)

  data$cover_pct <- as.numeric(total)
  data$cover <- as.integer(total >= threshold)

  if (keep_categories) {
    for (cat in categories) data[[paste0("ha_", cat, "_pct")]] <- cat_pct[, cat]
  }

  data
}
