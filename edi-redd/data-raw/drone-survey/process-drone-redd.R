library(tidyverse)
library(readxl)

xy_data_path <- here::here("edi-redd", "data-raw", "drone-survey", "2024 Aerial Chinook Salmon Redd Survey XY Data.xlsx")

raw_redd_lfc <- read_excel(xy_data_path, sheet = "LFC") |>
  mutate(channel_location = "LFC") |>
  janitor::clean_names() |>
  rename(latitude = lattitude) # LFC sheet has "Lattitude" typo; without this rename,
  # clean_names() produces a separate "lattitude" column and bind_rows() silently
  # splits the coordinate data across two columns instead of stacking it into one

raw_redd_hfc <- read_excel(xy_data_path, sheet = "HFC") |>
  mutate(channel_location = "HFC") |>
  janitor::clean_names()

raw_redd <- bind_rows(raw_redd_hfc, raw_redd_lfc)

### QC ----

# expected bounding box for the Feather River survey area (with some buffer);
# points outside this are almost certainly a data entry/digitizing error
feather_river_bbox <- list(
  lon = c(-121.7, -121.5),
  lat = c(39.3, 39.6)
)

qc_flags <- raw_redd |>
  mutate(
    row_id = row_number(),
    missing_location = is.na(location) | location == "",
    missing_date = is.na(survey_date),
    missing_coords = is.na(longitude) | is.na(latitude),
    coords_out_of_bounds = !missing_coords & (
      longitude < feather_river_bbox$lon[1] | longitude > feather_river_bbox$lon[2] |
        latitude < feather_river_bbox$lat[1] | latitude > feather_river_bbox$lat[2]
    ),
    date_out_of_season = !missing_date & (
      survey_date < as.Date("2024-09-01") | survey_date > as.Date("2024-11-30")
    )
  )

duplicate_points <- qc_flags |>
  filter(duplicated(pick(location, survey_date, longitude, latitude)))

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
if (qc_summary$missing_date > 0) warning(qc_summary$missing_date, " row(s) missing survey_date")
if (qc_summary$missing_coords > 0) warning(qc_summary$missing_coords, " row(s) missing coordinates")
if (qc_summary$coords_out_of_bounds > 0) warning(qc_summary$coords_out_of_bounds, " row(s) with coordinates outside the expected Feather River survey area")
if (qc_summary$date_out_of_season > 0) warning(qc_summary$date_out_of_season, " row(s) with survey_date outside the expected 2024 survey season")
if (qc_summary$duplicate_points > 0) warning(qc_summary$duplicate_points, " duplicate location/date/coordinate row(s) found")

### Compile final dataset ----

# drop only exact row-level duplicates; rows flagged above are kept but should
# be reviewed manually against the flags in qc_flags before treating as final
drone_redd_clean <- qc_flags |>
  distinct(location, survey_date, longitude, latitude, channel_location, .keep_all = TRUE) |>
  select(location, survey_date, longitude, latitude, channel_location) |>
  arrange(channel_location, location, survey_date)

write_csv(drone_redd_clean, here::here("edi-redd", "data-raw", "drone-survey", "drone_redd_clean.csv"))
