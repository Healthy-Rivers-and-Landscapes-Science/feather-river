# Publish stage for the 2024-2025 ground survey data.
#
# Puts ground_redd_clean.csv into the exact format of the published
# edi.1802 table `redd_observation_w_zeros.csv` (same 19 columns, names, order
# and types), so the new rows can be appended to it. Location names are the
# published EDI names (`edi_location`, from the ground crosswalk).
#
# Output: data/publish/ground_redd_observation_2024_2025.csv
#
# NOT done here: zero-redd rows. The published table's zeros come from a record
# of which sites were surveyed in which weeks (survey_site_dates.csv); the
# 2024/2025 ground workbooks only list redds that were found, so there is
# nothing to build zeros from yet (see the note at the bottom).
library(tidyverse)

project_dir   <- here::here("edi-redd")
# the published edi.1802.4 tables (for the format/location/date checks below)
published_dir <- here::here("edi-redd", "archive_of_edi_1802.4_and_earlier", "data")
publish_dir   <- file.path(project_dir, "data", "publish")
dir.create(publish_dir, showWarnings = FALSE, recursive = TRUE)

ground_redd_clean <- read_csv(
  file.path(project_dir, "data", "clean", "ground_redd_clean.csv"),
  show_col_types = FALSE
)

published_cols <- names(read_csv(file.path(published_dir, "redd_observation_w_zeros.csv"),
                                 n_max = 0, show_col_types = FALSE))

# each ground row is one redd; fields the ground workbooks don't have
# (pot depth, elevation, GPS accuracy, boat point) are NA, as they are for
# most of the published rows
ground_publish <- ground_redd_clean |>
  transmute(
    date,
    location        = edi_location,
    number_redds    = 1,
    number_salmon   = number_of_fish_on_redd,
    depth_m         = water_depth_m,
    pot_depth_m     = NA_real_,
    velocity_m_s    = velocity_m_sec,
    percent_fines   = percent_fine_1cm,
    percent_small   = percent_small_1_5cm,
    percent_med     = percent_medium_6_15cm,
    percent_large   = percent_large_16_30cm,
    percent_boulder = percent_boulder_30cm,
    redd_width_m,
    redd_length_m,
    longitude,
    latitude,
    elevation_ft    = NA_real_,
    accuracy_ft     = NA_real_,
    boat_point      = NA
  ) |>
  arrange(date, location)

# The ground workbooks leave a substrate class blank when it was 0%: on every
# redd with substrate recorded, the non-blank classes add to 100 (812 of 817
# rows; the other 5 are 105 or 110), and the published 2014-2023 table has 0,
# not NA, for those classes. So blanks become 0 on redds that have any substrate
# recorded; redds with no substrate recorded (depth/velocity/substrate only
# measured on some redds) stay NA.
substrate_cols <- str_subset(names(ground_publish), "^percent_")
ground_publish <- ground_publish |>
  mutate(across(
    all_of(substrate_cols),
    \(x) if_else(is.na(x) & if_any(all_of(substrate_cols), \(y) !is.na(y)), 0, x)
  ))

### Checks ----

stopifnot(
  identical(names(ground_publish), published_cols),
  !anyNA(ground_publish$location),
  !anyNA(ground_publish$date)
)

# every location must already exist in the published package
published_sites <- read_csv(file.path(published_dir, "survey_site_area.csv"), show_col_types = FALSE)$location
unknown_sites <- setdiff(unique(ground_publish$location), published_sites)
if (length(unknown_sites) > 0) {
  warning("location(s) not in the published survey_site_area.csv: ", paste(unknown_sites, collapse = ", "))
}

# new rows must not overlap the dates already published
published_last_date <- max(read_csv(file.path(published_dir, "redd_observation_w_zeros.csv"),
                                    col_select = date, show_col_types = FALSE)$date)
if (min(ground_publish$date) <= published_last_date) {
  warning("ground rows on or before the last published date (", published_last_date, ")")
}

# same value ranges as the published columns (percent 0-100, non-negative sizes)
pct_cols <- str_subset(names(ground_publish), "^percent_")
bad_pct <- ground_publish |> filter(if_any(all_of(pct_cols), \(x) !is.na(x) & (x < 0 | x > 100)))
if (nrow(bad_pct) > 0) warning(nrow(bad_pct), " row(s) with a percent column outside 0-100")

# the substrate percentages should add to ~100 where they were recorded
pct_sum <- rowSums(ground_publish[pct_cols])
off_100 <- which(!is.na(pct_sum) & abs(pct_sum - 100) > 1)
if (length(off_100) > 0) print(ground_publish[off_100, c("date", "location", pct_cols)])
if (length(off_100) > 0) warning(length(off_100), " row(s) where the substrate percentages don't sum to 100")

write_csv(ground_publish, file.path(publish_dir, "ground_redd_observation_2024_2025.csv"), na = "NA")

print(ground_publish |> count(year = year(date), name = "n_redds"))
print(ground_publish |> summarise(across(everything(), \(x) sum(is.na(x)))) |> pivot_longer(everything(), names_to = "column", values_to = "n_na"))

### Zero-redd rows (not built yet) ----
# To add them, we need what survey_site_dates.csv holds for 2014-2023: for each
# year, which sites were walked in which survey week (start/end dates). Then, as
# edi-update-script.R did, any surveyed site-week with no redd gets a row with
# number_redds = 0. Without it, a site with no row in 2024/2025 can mean either
# "surveyed, no redds" or "not surveyed".
