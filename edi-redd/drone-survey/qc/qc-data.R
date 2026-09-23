# Script to QC the cleaned drone redd survey dataset. Reads the published
# clean CSV directly (not clean-data.R's in-memory objects) so QC can be
# re-run standalone against whatever is currently in data/clean.
library(tidyverse)

drone_redd_clean <- read_csv(
  here::here("edi-redd", "drone-survey", "data", "clean", "drone_redd_clean.csv"),
  show_col_types = FALSE
)

### QC ----

# expected bounding box for the Feather River survey area (with some buffer);
# points outside this are almost certainly a data entry/digitizing error
feather_river_bbox <- list(
  lon = c(-121.7, -121.5),
  lat = c(39.3, 39.6)
)

qc_flags <- drone_redd_clean |>
  mutate(
    row_id = row_number(),
    missing_location = is.na(location) | location == "",
    missing_date = is.na(date),
    # rows with n_redds == 0 are flight-schedule "surveyed, zero redds"
    # placeholders (see clean-data.R) - they have no coordinates by design,
    # so only flag missing coords on an actual redd point
    missing_coords = n_redds != 0 & (is.na(longitude) | is.na(latitude)),
    coords_out_of_bounds = !is.na(longitude) & !is.na(latitude) & (
      longitude < feather_river_bbox$lon[1] | longitude > feather_river_bbox$lon[2] |
        latitude < feather_river_bbox$lat[1] | latitude > feather_river_bbox$lat[2]
    ),
    # spawning season is Sep-Nov in any survey year, not just 2024 - checked
    # by month so this doesn't need updating each time a new year is added
    date_out_of_season = !missing_date & !(month(date) %in% 9:11)
  )

# clean-data.R already drops exact row-level duplicates before writing, so
# this should come back 0 - kept as a regression check on that step
duplicate_points <- qc_flags |>
  filter(duplicated(pick(location, date, longitude, latitude)))

qc_summary <- qc_flags |>
  summarise(
    n_rows = n(),
    missing_location = sum(missing_location),
    missing_date = sum(missing_date),
    missing_coords = sum(missing_coords),
    coords_out_of_bounds = sum(coords_out_of_bounds),
    date_out_of_season = sum(date_out_of_season),
    duplicate_points = nrow(duplicate_points)
  )

print(qc_summary)

if (qc_summary$missing_location > 0) warning(qc_summary$missing_location, " row(s) missing location")
if (qc_summary$missing_date > 0) warning(qc_summary$missing_date, " row(s) missing date")
if (qc_summary$missing_coords > 0) warning(qc_summary$missing_coords, " row(s) missing coordinates")
if (qc_summary$coords_out_of_bounds > 0) warning(qc_summary$coords_out_of_bounds, " row(s) with coordinates outside the expected Feather River survey area")
if (qc_summary$date_out_of_season > 0) warning(qc_summary$date_out_of_season, " row(s) with date outside the expected Sep-Nov survey season")
if (qc_summary$duplicate_points > 0) warning(qc_summary$duplicate_points, " duplicate location/date/coordinate row(s) found")

### Figures ----

drone_redd_clean |>
  group_by(date, location, channel_location) |>
  summarise(n_redds = sum(n_redds), .groups = "drop") |>
  ggplot() +
  geom_col(aes(x = date, y = n_redds, fill = channel_location)) +
  theme_minimal()
