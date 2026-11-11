# Script used to clean and wrangle the raw drone redd survey data into the
# clean data that gets written to data/clean and published. This script ONLY
# cleans - QC checks and figures live in qc/qc-data.R and run against the
# clean data written out below, not against this script directly.
library(janitor)
library(sf)

source(here::here("edi-redd", "ingest", "read-data.R"))

### Drone location -> published EDI location crosswalk ----

# Drone `location` names are kept as recorded; `edi_location` is added next to
# them so each drone redd can be tied to the location names in the published
# ground survey package (edi.1802). The mapping lives in a hand-editable CSV -
# one row per drone location - so changing a match (e.g. once Chris confirms
# the "proposed" ones) is an edit to that file, not to this script:
#   data/crosswalk/drone_to_edi_location_crosswalk.csv
#   columns: drone_location, edi_location, basis, note
location_crosswalk <- read_csv(
  here::here("edi-redd", "data", "crosswalk", "drone_to_edi_location_crosswalk.csv"),
  show_col_types = FALSE
)
stopifnot(!anyDuplicated(location_crosswalk$drone_location))

# same idea for the ground survey data, whose location names differ from both
# the drone names and EDI (e.g. "Bedrock Riffle" -> bedrock):
#   data/crosswalk/ground_to_edi_location_crosswalk.csv
#   columns: ground_location, edi_location, basis, note
ground_location_crosswalk <- read_csv(
  here::here("edi-redd", "data", "crosswalk", "ground_to_edi_location_crosswalk.csv"),
  show_col_types = FALSE
)
stopifnot(!anyDuplicated(ground_location_crosswalk$ground_location))

published_edi_sites <- union(
  read_csv(here::here("edi-redd", "archive_of_edi_1802.4_and_earlier", "data", "survey_site_area.csv"), show_col_types = FALSE)$location,
  read_csv(here::here("edi-redd", "archive_of_edi_1802.4_and_earlier", "data", "redd_observations.csv"), col_select = location, show_col_types = FALSE)$location
) |> unique()

bad_edi <- setdiff(na.omit(c(location_crosswalk$edi_location, ground_location_crosswalk$edi_location)), published_edi_sites)
if (length(bad_edi) > 0) {
  warning("crosswalk edi_location(s) not found in the published EDI data: ", paste(bad_edi, collapse = ", "))
}

# adds `edi_location` right after `location`; warns (rather than guessing) on
# any drone location the crosswalk doesn't cover
add_edi_location <- function(df, crosswalk = location_crosswalk, name_col = "drone_location") {
  out <- df |>
    left_join(select(crosswalk, all_of(c(name_col, "edi_location"))), by = c("location" = name_col)) |>
    relocate(edi_location, .after = location)
  missing_locs <- unique(out$location[is.na(out$edi_location)])
  if (length(missing_locs) > 0) {
    warning("no EDI location in the crosswalk for: ", paste(missing_locs, collapse = ", "))
  }
  out
}

# 2024 and 2025 are NOT byte-identical: 2024's LFC sheet has a "Lattitude"
# typo that 2025's does not (already spelled correctly), and the date column
# is named "Survey Date" in 2024 vs "Date" in 2025. Each year's actual columns
# are handled explicitly below rather than assumed to match, and both are
# standardized to `survey_date` so they can be bound together.
raw_redd_lfc <- raw_lfc |>
  mutate(channel_location = "LFC") |>
  janitor::clean_names() |>
  rename(latitude = lattitude) # 2024 LFC sheet has "Lattitude" typo; without this
# rename, clean_names() produces a separate "lattitude" column and bind_rows()
# silently splits the coordinate data across two columns instead of stacking
# it into one

raw_redd_hfc <- raw_hfc |>
  mutate(channel_location = "HFC") |>
  janitor::clean_names()

raw_redd_lfc_2025 <- raw_lfc_2025 |>
  mutate(channel_location = "LFC") |>
  janitor::clean_names() |>
  rename(survey_date = date)

raw_redd_hfc_2025 <- raw_hfc_2025 |>
  mutate(channel_location = "HFC") |>
  janitor::clean_names() |>
  rename(survey_date = date)

raw_redd <- bind_rows(raw_redd_hfc, raw_redd_lfc, raw_redd_hfc_2025, raw_redd_lfc_2025) |> glimpse()

### Compile clean redd point dataset ----

# drop only exact row-level duplicates; anything else should be reviewed
# manually against the flags in qc/qc-data.R before treating as final
drone_redd_clean <- raw_redd |>
  distinct(location, survey_date, longitude, latitude, channel_location, .keep_all = TRUE) |>
  select(location, survey_date, longitude, latitude, channel_location) |>
  arrange(channel_location, location, survey_date) |>
  rename(date = survey_date) |>
  mutate(survey_method = "drone") |>
  mutate(n_redds = 1) |> # every point is a redd. This is important for if we want to add surveyed dates that there were no redds.
  glimpse()

# not written yet - drone_redd_clean stays points-only until the
# flight-schedule zero-redd rows (no coordinates) are appended at the very end
# of this script

### Compile clean ground survey redd dataset ----

# Ground surveys are a separate, ongoing method run alongside the drone
# survey (see the note in ingest/read-data.R), not folded into
# drone_redd_clean - the same physical redd can be recorded by both methods
# at sites where they overlap, so summing/stacking the two would not be a
# valid total. Written out as its own file; how (or whether) the two get
# reconciled for publication is still an open question, not decided here.
#
# 2024's %Med column is named differently from 2025's %Medium column -
# rename before bind_rows so it doesn't silently split into two columns.
# 2024's %Boulder column also reads in as character (all values are still
# numeric-parseable; the column is just formatted as text in that workbook),
# which bind_rows() would otherwise error on when combined with 2025's
# numeric column.
raw_ground_2024_clean <- raw_ground_2024 |>
  clean_names() |>
  rename(percent_medium_6_15cm = percent_med_6_15cm) |>
  mutate(percent_boulder_30cm = as.numeric(percent_boulder_30cm))

raw_ground_2025_clean <- raw_ground_2025 |>
  clean_names()

ground_redd_clean <- bind_rows(raw_ground_2024_clean, raw_ground_2025_clean) |>
  rename(
    location  = riffle_name,
    latitude  = latitude_wgs_84,
    longitude = longitude_wgs_84
  ) |>
  mutate(
    date          = mdy(date),
    year          = year(date),
    survey_method = "ground"
  ) |>
  distinct(location, date, latitude, longitude, redd_number, .keep_all = TRUE) |>
  # TODO: confirm with Chris that every ground row is exactly one redd. The
  # workbooks' `Redd #` column is used above to drop duplicate rows but is not
  # kept, and number_redds = 1 is assumed for each row.
  mutate(number_redds = 1) |>
  select(
    location, date, year, latitude, longitude, survey_method,
    number_redds, survey_week, number_of_fish_on_redd,
    percent_boulder_30cm, percent_large_16_30cm, percent_medium_6_15cm,
    percent_small_1_5cm, percent_fine_1cm,
    redd_width_m, redd_length_m, velocity_m_sec, water_depth_m
  ) |>
  arrange(date, location) |>
  glimpse()

ground_redd_clean <- add_edi_location(ground_redd_clean, ground_location_crosswalk, "ground_location")

write_csv(ground_redd_clean, here::here("edi-redd", "data", "clean", "ground_redd_clean.csv"))

### Format ground redds like the published redd_observation_w_zeros table ----

# Puts the cleaned ground redds into the exact format of the published edi.1802
# table `redd_observation_w_zeros.csv` (same 19 columns, names and order), so the
# new rows can be appended to it. `location` is the published EDI name
# (`edi_location`, from the ground crosswalk).
#
# NOT done here: zero-redd rows. The published table's zeros come from a record
# of which sites were surveyed in which weeks (survey_site_dates.csv); the
# 2024/2025 ground workbooks only list redds that were found, so there is
# nothing to build zeros from yet. Without it, a site with no row in
# 2024/2025 can mean either "surveyed, no redds" or "not surveyed".
published_dir <- here::here("edi-redd", "archive_of_edi_1802.4_and_earlier", "data")
published_cols <- names(read_csv(file.path(published_dir, "redd_observation_w_zeros.csv"),
                                 n_max = 0, show_col_types = FALSE))

# each ground row is one redd; fields the ground workbooks don't have
# (pot depth, elevation, GPS accuracy, boat point) are NA, as they are for
# most of the published rows
ground_redd_observation <- ground_redd_clean |>
  transmute(
    date,
    location        = edi_location,
    number_redds,
    number_salmon  = number_of_fish_on_redd,
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
substrate_cols <- str_subset(names(ground_redd_observation), "^percent_")
ground_redd_observation <- ground_redd_observation |>
  mutate(across(
    all_of(substrate_cols),
    \(x) if_else(is.na(x) & if_any(all_of(substrate_cols), \(y) !is.na(y)), 0, x)
  ))

# checks against the published package
stopifnot(
  identical(names(ground_redd_observation), published_cols),
  !anyNA(ground_redd_observation$location),
  !anyNA(ground_redd_observation$date)
)

# every location must already exist in the published package
unknown_sites <- setdiff(unique(ground_redd_observation$location), read_csv(file.path(published_dir, "survey_site_area.csv"), show_col_types = FALSE)$location)
if (length(unknown_sites) > 0) {
  warning("ground location(s) not in the published survey_site_area.csv: ", paste(unknown_sites, collapse = ", "))
}

# new rows must not overlap the dates already published
published_last_date <- max(read_csv(file.path(published_dir, "redd_observation_w_zeros.csv"),
                                    col_select = date, show_col_types = FALSE)$date)
if (min(ground_redd_observation$date) <= published_last_date) {
  warning("ground rows on or before the last published date (", published_last_date, ")")
}

# percent columns in range, and substrate classes adding to ~100
bad_pct <- ground_redd_observation |> filter(if_any(all_of(substrate_cols), \(x) !is.na(x) & (x < 0 | x > 100)))
if (nrow(bad_pct) > 0) warning(nrow(bad_pct), " ground row(s) with a percent column outside 0-100")

pct_sum <- rowSums(ground_redd_observation[substrate_cols])
off_100 <- which(!is.na(pct_sum) & abs(pct_sum - 100) > 1)
if (length(off_100) > 0) {
  print(ground_redd_observation[off_100, c("date", "location", substrate_cols)])
  warning(length(off_100), " ground row(s) where the substrate percentages don't sum to 100")
}

dir.create(here::here("edi-redd", "data", "publish"), showWarnings = FALSE, recursive = TRUE)
write_csv(ground_redd_observation, here::here("edi-redd", "data", "publish", "ground_redd_observation_2024_2025.csv"), na = "NA")

### Compile clean flight route schedule ----

# Tidies the flight route schedule(s) into a long table; redd_total == 0 rows
# get folded into drone_redd_clean at the end of this script as "surveyed,
# zero redds" placeholder points (no coordinates - see that section).
#
# The raw sheet is not a normalized table - LFC and HFC sit side by side
# (cols 1-26 and 27-42), each block mixing "mission group" label rows (e.g.
# "Upper Cottonwood to Table Mountain", every data cell blank) with
# individual-location rows underneath, and repeating (date, Redd Total)
# column pairs per flight (#1-#12) - see row 2 for the labels.
#
# The two blocks are NOT laid out the same way. LFC's #N/Redd Total labels
# alternate cleanly, so every #N column pairs with the very next column. HFC's
# do not - several #N columns in a row have no adjacent "Redd Total" (an
# allocated-but-unflown flight slot, always blank). Pairing by fixed column
# offset instead of by header label silently misaligns those columns - in
# testing this mistake actually paired a real redd count with the following
# empty column and read the count as an Excel date serial. Pairing strictly by
# header label instead - only when a "#N" column is immediately followed by a
# "Redd Total" column - avoids that.
parse_flight_schedule_block <- function(raw, cols, channel) {
  block <- raw[, cols]
  names(block) <- paste0("c", seq_along(block))

  header <- as.character(unlist(block[2, ]))  # row 2: block title, then #N / Redd Total labels
  body   <- block[-c(1, 2), ]                 # drop title row + label row

  pair_idx <- which(str_starts(header, "#") & lead(header) == "Redd Total")
  skipped  <- setdiff(which(str_starts(header, "#")), pair_idx)
  message(
    channel, ": ", length(pair_idx), " valid (date, Redd Total) column pair(s); ",
    length(skipped), " unpaired placeholder column(s) skipped (",
    paste(header[skipped], collapse = ", "), ")"
  )

  # a row is a "mission group" header iff every data cell is blank; otherwise
  # it's an individual location row and inherits the most recent group label
  is_group_header <- apply(body[, -1], 1, function(r) all(is.na(r)))
  body$mission_group <- NA_character_
  current_group <- NA_character_
  for (i in seq_len(nrow(body))) {
    if (is_group_header[i]) {
      current_group <- body$c1[i]
    } else {
      body$mission_group[i] <- current_group
    }
  }
  individual <- body[!is_group_header, ]

  map_dfr(pair_idx, function(k) {
    tibble(
      location         = individual$c1,
      mission_group    = individual$mission_group,
      mission_label    = header[k],
      channel_location = channel,
      date_serial      = suppressWarnings(as.numeric(individual[[paste0("c", k)]])),
      redd_total       = suppressWarnings(as.numeric(individual[[paste0("c", k + 1)]]))
    )
  }) |>
    filter(!is.na(date_serial)) |>
    mutate(date = as.Date(date_serial, origin = "1899-12-30")) |>
    select(location, mission_group, channel_location, mission_label, date, redd_total)
}

flight_schedule_2025 <- bind_rows(
  parse_flight_schedule_block(raw_flight_schedule_2025, cols = 1:26,  channel = "LFC"),
  parse_flight_schedule_block(raw_flight_schedule_2025, cols = 27:42, channel = "HFC")
) |>
  mutate(redd_total_source = "flight schedule") |>
  # TEMPORARY per-name fix, not a general rule: "Hatchery" is used for two
  # different, adjacent stretches of river and reports two different
  # non-zero redd totals on the same date depending on which flight route it
  # falls under (e.g. 2025-09-24: 41 under "Top of Auditorium to Upper
  # Cottonwood" vs 5 under "Upper Cottonwood to Table Mountain") - these are
  # not duplicates of each other. Disambiguated by mission group until the
  # actual sub-locations get proper names.
  mutate(location = if_else(location == "Hatchery",
                            paste0(mission_group, "-hatchery"),
                            location))

# 2024 schedule: dates only (no redd totals), so how many redds each flight
# found is INFERRED from the redd points instead - the same location on the
# same date with redd points = that many redds, and a scheduled flight with no
# points at all = a true zero. (Checked on 2025, where the schedule does give
# totals: its totals equal the point counts in 148 of 168 location-days with
# redds, and every 0 in the schedule had no points.) Where a flight has no points on
# its scheduled date but does the next day, the total is left NA rather than
# calling it a zero - the date is more likely off by a day than the site empty.
parse_flight_schedule_2024 <- function(raw) {
  names(raw) <- paste0("c", seq_len(ncol(raw)))
  date_cols  <- setdiff(names(raw), "c1")
  channel <- NA_character_; group <- NA_character_; labels <- NULL
  out <- vector("list", nrow(raw))

  for (i in seq_len(nrow(raw))) {
    name <- raw$c1[i]
    if (is.na(name) || str_detect(name, "Survey Week and Survey Mission")) next
    vals <- unlist(raw[i, date_cols], use.names = FALSE)

    if (str_detect(name, "^Flight Routes")) {          # LFC / HFC header row with the #1..#11 labels
      channel <- str_extract(name, "LFC|HFC"); group <- NA_character_
      labels  <- setNames(as.character(vals), date_cols)
      next
    }
    if (all(is.na(vals))) { group <- name; next }       # mission group label row

    serial <- suppressWarnings(as.numeric(vals))
    ok <- !is.na(serial)
    out[[i]] <- tibble(
      sched_name       = name,
      mission_group    = group,
      channel_location = channel,
      mission_label    = unname(labels[date_cols][ok]),
      date             = as.Date(serial[ok], origin = "1899-12-30")
    )
  }
  bind_rows(out)
}

flight_schedule_2024 <- if (!is.null(raw_flight_schedule_2024)) {
  # combined / differently-spelled rows -> one row per location (hand-editable)
  schedule_2024_name_map <- read_csv(
    here::here("edi-redd", "data", "crosswalk", "schedule_2024_name_map.csv"),
    show_col_types = FALSE
  )

  points_by_day <- drone_redd_clean |>
    mutate(date = as.Date(date)) |>
    count(location, date, name = "n_points")
  points_next_day <- points_by_day |> mutate(date = date - 1) |> rename(n_next_day = n_points)

  parse_flight_schedule_2024(raw_flight_schedule_2024) |>
    left_join(schedule_2024_name_map, by = c("sched_name" = "schedule_name"), relationship = "many-to-many") |>
    mutate(location = coalesce(location, sched_name)) |>
    # a location listed under two missions on the same date (e.g. Hatchery)
    # is one flight-day for the redd count, so collapse to one row
    group_by(location, channel_location, date) |>
    summarise(
      mission_group = na_if(paste(unique(na.omit(mission_group)), collapse = "; "), ""),
      mission_label = paste(unique(mission_label), collapse = "/"),
      .groups = "drop"
    ) |>
    left_join(points_by_day,   by = c("location", "date")) |>
    left_join(points_next_day, by = c("location", "date")) |>
    mutate(
      redd_total = case_when(
        !is.na(n_points)   ~ as.numeric(n_points),
        !is.na(n_next_day) ~ NA_real_,
        TRUE               ~ 0
      ),
      redd_total_source = "inferred from redd points"
    ) |>
    select(location, mission_group, channel_location, mission_label, date, redd_total, redd_total_source,
           n_next_day)
} else {
  NULL
}

date_off_by_one <- flight_schedule_2024 |> filter(is.na(redd_total))
if (nrow(date_off_by_one) > 0) {
  warning(nrow(date_off_by_one), " 2024 scheduled flight(s) have no redd points on the scheduled date but do the next day - redd_total left NA (not a zero): ",
          paste0(date_off_by_one$location, " ", date_off_by_one$date, collapse = "; "))
}

flight_schedule_clean <- bind_rows(flight_schedule_2025, select(flight_schedule_2024, -n_next_day))

# sanity checks - both should be empty/zero once the above is correct
duplicate_schedule_rows <- flight_schedule_clean |>
  count(location, channel_location, date) |>
  filter(n > 1)
if (nrow(duplicate_schedule_rows) > 0) {
  warning(nrow(duplicate_schedule_rows), " location/channel/date combination(s) still have more than one redd_total - see duplicate_schedule_rows")
}
if (any(!format(flight_schedule_clean$date, "%Y") %in% c("2024", "2025"))) {
  warning("flight_schedule_clean has date(s) outside 2024/2025 - likely a column-pairing error")
}

flight_schedule_clean <- add_edi_location(flight_schedule_clean)

write_csv(flight_schedule_clean,here::here("edi-redd", "data", "clean", "flight_schedule_clean.csv"))

### Compile flight route mission shapefiles ----
# Published as pure route geometry, keyed by `mission` (the name each flight
# route shapefile was given by hand in the field). There is deliberately no
# `location` or `n_redds` here:
#   - Redd `location` comes from the ground redd survey location map (see
#     drone_redd_clean), NOT from the flight route boundaries - several
#     routes cover multiple spawning locations, and one location (e.g.
#     Hatchery) can sit under more than one route.
#   - A per-mission redd count would sum every survey date and depend on a
#     point-in-polygon join that isn't the basis for location assignment.
# If a mission-to-location link is ever needed, take it from the flight
# schedule's `mission_group` (flight_schedule_clean) instead of re-deriving it
# spatially.

drone_flight_routes <- map(mission_files, function(f) {
  st_read(f, quiet = TRUE) |>
    st_zm() |>
    st_transform(4326) |>
    transmute(mission = tools::file_path_sans_ext(basename(f)))
}) |>
  list_rbind() |>
  st_as_sf()

st_write(
  drone_flight_routes,
  here::here("edi-redd", "data", "clean", "drone_flight_routes_compiled.shp"),
  delete_dsn = TRUE,
  quiet = TRUE
)

### Add flight-schedule "surveyed, zero redds" rows to drone_redd_clean ----

# flight_schedule_clean rows with redd_total == 0 record that a location was
# actually flown that date and no redds were found - a real "true zero" that
# drone_redd_clean can't otherwise tell apart from "never surveyed here."
# Only 0-count rows are added; anything >0 is already represented by actual
# redd points above, so re-adding it here would double count. These rows have
# no coordinates.
zero_redd_rows <- flight_schedule_clean |>
  filter(redd_total == 0) |>
  transmute(
    location, date,
    longitude = NA_real_,
    latitude  = NA_real_,
    channel_location,
    survey_method = "drone",
    n_redds = 0
  )

# sanity check - a location/date/channel that already has an actual redd
# point should never also show up here as a zero-redd schedule row; flag
# rather than silently drop if it ever does
zero_redd_conflicts <- zero_redd_rows |>
  semi_join(drone_redd_clean, by = c("location", "date", "channel_location"))
if (nrow(zero_redd_conflicts) > 0) {
  warning(nrow(zero_redd_conflicts), " flight-schedule zero-redd row(s) conflict with an existing drone_redd_clean point - see zero_redd_conflicts")
}

drone_redd_clean <- bind_rows(drone_redd_clean, zero_redd_rows) |>
  add_edi_location() |>
  arrange(channel_location, location, date) |>
  glimpse()

write_csv(drone_redd_clean, here::here("edi-redd", "data", "clean", "drone_redd_clean.csv"))

