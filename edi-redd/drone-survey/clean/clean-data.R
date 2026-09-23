# Script used to clean and wrangle the raw drone redd survey data into the
# clean data that gets written to data/clean and published. This script ONLY
# cleans - QC checks and figures live in qc/qc-data.R and run against the
# clean data written out below, not against this script directly.
library(janitor)
library(sf)

source(here::here("edi-redd", "drone-survey", "ingest", "read-data.R"))

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

raw_redd <- bind_rows(raw_redd_hfc, raw_redd_lfc, raw_redd_hfc_2025, raw_redd_lfc_2025)

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

# not written yet - the mission spatial join below needs real point
# geometries, so drone_redd_clean stays points-only until the flight-schedule
# zero-redd rows (no coordinates) are appended at the very end of this script

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
  select(
    location, date, year, latitude, longitude, survey_method,
    redd_number, survey_week, number_of_fish_on_redd,
    percent_boulder_30cm, percent_large_16_30cm, percent_medium_6_15cm,
    percent_small_1_5cm, percent_fine_1cm,
    redd_width_m, redd_length_m, velocity_m_sec, water_depth_m
  ) |>
  arrange(date, location) |>
  glimpse()

write_csv(ground_redd_clean, here::here("edi-redd", "drone-survey", "data", "clean", "ground_redd_clean.csv"))

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

flight_schedule_2024 <- if (!is.null(raw_flight_schedule_2024)) {
  # Assumes the same wide LFC (cols 1-26) / HFC (cols 27-42) layout as 2025 -
  # verify this against the actual file once it arrives rather than trusting
  # the assumption.
  bind_rows(
    parse_flight_schedule_block(raw_flight_schedule_2024, cols = 1:26,  channel = "LFC"),
    parse_flight_schedule_block(raw_flight_schedule_2024, cols = 27:42, channel = "HFC")
  )
} else {
  NULL
}

flight_schedule_clean <- bind_rows(
  parse_flight_schedule_block(raw_flight_schedule_2025, cols = 1:26,  channel = "LFC"),
  parse_flight_schedule_block(raw_flight_schedule_2025, cols = 27:42, channel = "HFC"),
  flight_schedule_2024
) |>
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

write_csv(flight_schedule_clean, here::here("edi-redd", "drone-survey", "data", "clean", "flight_schedule_clean.csv"))

### Compile flight route mission shapefiles ----
# NOTE: this section intentionally uses only drone_redd_clean. Ground surveys
# are walked, not flown, so they have no corresponding mission flight route
# polygon to spatially join against.

# each mission shapefile is a drone flight route polygon named by hand in the
# field; those names mostly match `location` in drone_redd_clean but a few
# missions were flown as one combined route over several locations (e.g.
# "Low Aud to Upp Aud" covers Lower/Middle/Upper Auditorium). Rather than
# guess a name crosswalk, spatially join each mission polygon against the
# redd points it actually contains and use that to assign location name(s).

mission_polys <- map(mission_files, function(f) {
  st_read(f, quiet = TRUE) |>
    st_zm() |>
    st_transform(4326) |>
    transmute(mission = tools::file_path_sans_ext(basename(f)), feature_id = row_number())
}) |>
  list_rbind() |>
  st_as_sf()

redd_pts <- drone_redd_clean |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |>
  mutate(pt_id = row_number())

# 2m buffer only absorbs floating-point/edge-snapping noise between a mission
# polygon and the points recorded inside it; it's too small to bleed into a
# neighboring mission's polygon
mission_polys_buf <- mission_polys |>
  st_transform(3310) |>
  st_buffer(2) |>
  st_transform(4326)

matches_raw <- st_join(mission_polys_buf, redd_pts, join = st_intersects) |>
  st_drop_geometry()

# A handful of redd points sit close enough to a mission boundary to
# intersect two adjacent missions' 2m buffers at once (e.g. some "G95 West
# Bottom" points are caught by both "G95 East Top" and "G95 West"). Left as
# is, that redd gets counted under both missions' n_redds. Resolve each such
# point to whichever mission's ACTUAL (unbuffered) polygon it is physically
# nearest to - "nearest mission wins" - so every redd is assigned to exactly
# one mission.
ambiguous_pt_ids <- matches_raw |>
  filter(!is.na(pt_id)) |>
  distinct(pt_id, mission, feature_id) |>
  count(pt_id) |>
  filter(n > 1) |>
  pull(pt_id)

if (length(ambiguous_pt_ids) > 0) {
  redd_pts_m      <- st_transform(redd_pts, 3310)
  mission_polys_m <- st_transform(mission_polys, 3310)

  candidate_dists <- matches_raw |>
    filter(pt_id %in% ambiguous_pt_ids) |>
    distinct(pt_id, location, mission, feature_id) |>
    rowwise() |>
    mutate(
      dist_m = as.numeric(st_distance(
        st_geometry(redd_pts_m)[redd_pts_m$pt_id == pt_id],
        st_geometry(mission_polys_m)[mission_polys_m$mission == mission & mission_polys_m$feature_id == feature_id]
      ))
    ) |>
    ungroup() |>
    # Name-based rules take priority over distance, ranked most to least
    # specific:
    #   0. EXACT match (trimmed, case-insensitive) between a candidate
    #      mission's name and the redd's own `location` - e.g. a redd
    #      recorded under location "Trailer Park" should be assigned to the
    #      "Trailer Park" mission even where the "Mathews" mission's polygon
    #      happens to be marginally closer at that point.
    #   1. The `location` starts with a candidate mission's name - i.e. the
    #      location is a named sub-area of that mission (e.g. location "G95
    #      West Bottom" is part of the "G95 West" mission, not "G95 East
    #      Top", regardless of which polygon edge is nearer).
    #   2. No name-based rule applies - fall back to nearest distance.
    mutate(
      location_norm = str_to_lower(str_trim(location)),
      mission_norm  = str_to_lower(str_trim(mission)),
      match_rank = case_when(
        mission_norm == location_norm        ~ 0L,
        str_starts(location_norm, mission_norm) ~ 1L,
        TRUE                                  ~ 2L
      )
    )

  winners <- candidate_dists |>
    group_by(pt_id) |>
    arrange(match_rank, dist_m, .by_group = TRUE) |>
    slice(1) |>
    ungroup()

  # what would nearest-distance ALONE have picked, purely so the log below
  # can flag the cases where a name-based rule actually changed the outcome
  nearest_only <- candidate_dists |>
    group_by(pt_id) |>
    slice_min(dist_m, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(pt_id, nearest_mission = mission)

  ambiguous_resolution_log <- winners |>
    left_join(nearest_only, by = "pt_id") |>
    mutate(
      resolved_by = case_when(
        match_rank == 0L ~ "exact name match",
        match_rank == 1L ~ "location starts with mission name",
        TRUE             ~ "nearest distance"
      ),
      changed_from_nearest = mission != nearest_mission
    ) |>
    left_join(
      st_drop_geometry(redd_pts_m) |> select(pt_id, longitude, latitude),
      by = "pt_id"
    ) |>
    left_join(
      candidate_dists |>
        arrange(pt_id, dist_m) |>
        group_by(pt_id) |>
        summarise(all_candidates = paste0(mission, " (", round(dist_m), "m)", collapse = " | "), .groups = "drop"),
      by = "pt_id"
    ) |>
    select(pt_id, location, longitude, latitude, assigned_mission = mission,
           resolved_by, changed_from_nearest, all_candidates)

  message(
    nrow(ambiguous_resolution_log),
    " redd point(s) intersected more than one mission's buffer. ",
    sum(ambiguous_resolution_log$changed_from_nearest),
    " flipped away from the nearest-distance pick by a name-based rule; the rest kept nearest distance:"
  )
  print(ambiguous_resolution_log |> select(pt_id, location, assigned_mission, resolved_by, all_candidates))

  write_csv(
    ambiguous_resolution_log,
    here::here("edi-redd", "drone-survey", "data", "clean", "diagnostics", "ambiguous_mission_matches.csv")
  )

  winners <- winners |> select(pt_id, mission, feature_id)

  # keep every row for missions with zero matches (pt_id is NA) and every
  # non-ambiguous point match untouched; for ambiguous points, keep only the
  # winning row (name-match override where one applies, else nearest)
  matches_raw <- bind_rows(
    matches_raw |> filter(is.na(pt_id) | !(pt_id %in% ambiguous_pt_ids)),
    matches_raw |> semi_join(winners, by = c("pt_id", "mission", "feature_id"))
  )
}

matches <- matches_raw |>
  count(mission, feature_id, location, name = "n_redds")

# one row per mission x matched location; missions with no drone_redd_clean
# points inside them (new mission areas not yet reflected in the redd data)
# keep their own mission name as the location so nothing is silently dropped
location_lookup <- matches |>
  mutate(matched = !is.na(location), location = if_else(matched, location, mission)) |>
  arrange(mission, feature_id, desc(n_redds))

multi_location_missions <- location_lookup |>
  count(mission, feature_id) |>
  filter(n > 1)
if (nrow(multi_location_missions) > 0) {
  message("Missions spanning more than one drone_redd_clean location:")
  print(multi_location_missions)
}

unmatched_missions <- location_lookup |>
  filter(!matched) |>
  distinct(mission)
if (nrow(unmatched_missions) > 0) {
  warning(nrow(unmatched_missions), " mission shapefile(s) had no matching drone_redd_clean location and kept their own mission name: ",
          paste(unmatched_missions$mission, collapse = ", "))
}

# mission = mission name, which overlaps with location name but not always. TODO - do we need this?
# location = redd location name, from redd dataset
# NOTE: there are redundant polygons in this approach because it is mapped to the location.
# `matched` kept even though it's redundant with n_redds in most rows -
# qc/visualize-drone-redd.R relies on it to tell a genuinely-unmatched
# mission (location fell back to the mission's own name, n_redds is a join
# artifact rather than a real count) apart from a mission whose one real
# matched location just happens to share its name.
drone_flight_routes <- mission_polys |>
  left_join(location_lookup, by = c("mission", "feature_id")) |>
  select(mission, location, n_redds)

st_write(
  drone_flight_routes,
  here::here("edi-redd", "drone-survey", "data", "clean", "drone_flight_routes_compiled.shp"),
  delete_dsn = TRUE,
  quiet = TRUE
)

### Add flight-schedule "surveyed, zero redds" rows to drone_redd_clean ----

# flight_schedule_clean rows with redd_total == 0 record that a location was
# actually flown that date and no redds were found - a real "true zero" that
# drone_redd_clean can't otherwise tell apart from "never surveyed here."
# Only 0-count rows are added; anything >0 is already represented by actual
# redd points above, so re-adding it here would double count. These rows have
# no flight coordinates, so they're appended after (not before) the mission
# spatial join above, which needs real point geometries to work.
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
  arrange(channel_location, location, date) |>
  glimpse()

write_csv(drone_redd_clean, here::here("edi-redd", "drone-survey", "data", "clean", "drone_redd_clean.csv"))
