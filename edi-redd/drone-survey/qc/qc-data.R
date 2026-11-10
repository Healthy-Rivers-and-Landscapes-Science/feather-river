# Script to QC the cleaned drone redd survey dataset. Reads the published
# clean CSV directly (not clean-data.R's in-memory objects) so QC can be
# re-run standalone against whatever is currently in data/clean.
library(tidyverse)
library(ggalluvial)

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

diagnostics_dir <- here::here("edi-redd", "drone-survey", "data", "clean", "diagnostics")

drone_redd_clean |>
  group_by(date, location, channel_location) |>
  summarise(n_redds = sum(n_redds), .groups = "drop") |>
  ggplot() +
  geom_col(aes(x = date, y = n_redds, fill = channel_location)) +
  theme_minimal()

# summary charts saved to data/clean/diagnostics/

channel_colors <- c(HFC = "#2a78d6", LFC = "#eb6834")

redds_by_location <- drone_redd_clean |>
  group_by(location, channel_location) |>
  summarise(n_redds = sum(n_redds), .groups = "drop") |>
  mutate(location = fct_reorder(location, n_redds, .fun = sum))

p_by_location <- ggplot(redds_by_location, aes(x = n_redds, y = location, fill = channel_location)) +
  geom_col() +
  scale_fill_manual(values = channel_colors, name = NULL) +
  labs(
    title = "Drone-surveyed redds by location",
    x = "Number of redds", y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")

p_by_location

ggsave(file.path(diagnostics_dir, "redds_by_location.png"), p_by_location, width = 8, height = 10, dpi = 150)

redds_by_date <- drone_redd_clean |>
  group_by(date, channel_location) |>
  summarise(n_redds = sum(n_redds), .groups = "drop")

p_by_date <- ggplot(redds_by_date, aes(x = date, y = n_redds, fill = channel_location)) +
  geom_col() +
  scale_fill_manual(values = channel_colors, name = NULL) +
  labs(
    title = "Drone-surveyed redds by survey date",
    x = NULL, y = "Number of redds"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")

p_by_date

ggsave(file.path(diagnostics_dir, "redds_by_date.png"), p_by_date, width = 9, height = 5, dpi = 150)

### Location name figures ----

# Goal: every drone and ground survey location name maps to a location name in
# the published EDI package (edi.1802). These figures show how each source name
# flows to its EDI name, using the hand-editable crosswalk files in
# data/crosswalk/ (the same ones clean-data.R applies). Names that matched EDI
# exactly are gray; the matches still awaiting confirmation are colored, so the
# ones to check stand out.

crosswalk_dir <- here::here("edi-redd", "drone-survey", "data", "crosswalk")
drone_xw  <- read_csv(file.path(crosswalk_dir, "drone_to_edi_location_crosswalk.csv"), show_col_types = FALSE)
ground_xw <- read_csv(file.path(crosswalk_dir, "ground_to_edi_location_crosswalk.csv"), show_col_types = FALSE)

ground_redd_clean <- read_csv(
  here::here("edi-redd", "drone-survey", "data", "clean", "ground_redd_clean.csv"),
  show_col_types = FALSE
)

basis_cols <- c(
  "exact name match"          = "#c9ccd1",
  "proposed"                  = "#1f4e9c",
  "low - confirm"             = "#e8590c",
  "pending Hatchery decision" = "#7b3fa0"
)

# One equal-width flow per source name (so every name stays readable and
# many-to-one matches, e.g. three G95 names -> one EDI site, are easy to see);
# the number of redds is in each label.
plot_name_alluvial <- function(df, from_label, title, subtitle) {
  # strata on the left are ordered by the EDI name they map to, so exact
  # matches run straight across and only the non-matching names cross
  from_levels <- df |> arrange(edi_location, name_label) |> pull(name_label)
  df <- df |>
    mutate(
      from_name = factor(name_label, levels = from_levels),
      edi_name  = factor(edi_location, levels = sort(unique(edi_location))),
      basis     = factor(basis, levels = names(basis_cols))
    )

  ggplot(df, aes(axis1 = from_name, axis2 = edi_name, y = 1)) +
    geom_alluvium(aes(fill = basis), width = 0.45, alpha = 0.9) +
    geom_stratum(width = 0.45, fill = "white", color = "grey60", linewidth = 0.3) +
    geom_text(stat = "stratum", aes(label = after_stat(stratum)), size = 2.6) +
    scale_x_discrete(limits = c(from_label, "Published EDI location name"), expand = c(0.3, 0.05)) +
    scale_fill_manual(values = basis_cols, drop = FALSE, name = "How it was matched") +
    labs(title = title, subtitle = subtitle) +
    theme_minimal(base_size = 10) +
    theme(legend.position = "top", panel.grid = element_blank(),
          axis.text.y = element_blank(), axis.title = element_blank())
}

# drone: every name in the crosswalk, with its redd count (0 = only appears on
# zero-redd survey days)
drone_name_flows <- drone_xw |>
  left_join(
    drone_redd_clean |> group_by(drone_location = location) |> summarise(n_redds = sum(n_redds), .groups = "drop"),
    by = "drone_location"
  ) |>
  mutate(n_redds = replace_na(n_redds, 0), name_label = paste0(drone_location, " (", n_redds, ")"))

p_drone_names <- plot_name_alluvial(
  drone_name_flows, "Drone redd location name (redds)",
  "Drone redd location names -> published EDI location names",
  "Gray = exact name match; colored = proposed match to confirm with Chris."
)
ggsave(file.path(diagnostics_dir, "drone_location_names_to_edi.png"), p_drone_names, width = 9, height = 15, dpi = 110)

# ground: each row is one redd
ground_name_flows <- ground_xw |>
  left_join(count(ground_redd_clean, ground_location = location, name = "n_redds"), by = "ground_location") |>
  mutate(n_redds = replace_na(n_redds, 0L), name_label = paste0(ground_location, " (", n_redds, ")"))

p_ground_names <- plot_name_alluvial(
  ground_name_flows, "Ground survey location name (redds)",
  "Ground survey location names -> published EDI location names",
  "Gray = exact name match; colored = proposed match to confirm with Chris."
)
ggsave(file.path(diagnostics_dir, "ground_location_names_to_edi.png"), p_ground_names, width = 9, height = 9, dpi = 110)

### Survey effort and method overlap ----

# every drone location x survey date: filled = redds found, X = flown with no
# redds found (a "true zero" - from the flight schedule in 2025, inferred from
# a scheduled flight with no redd points in 2024), blank = no flight recorded.
# A zero next to filled cells at the same site on neighboring dates is expected;
# a blank in the middle of a run of surveyed dates is worth a look.
drone_effort <- drone_redd_clean |>
  mutate(date = as.Date(date), year = year(date)) |>
  group_by(channel_location, year, location, date) |>
  summarise(n_redds = sum(n_redds), .groups = "drop")

p_effort <- ggplot(drone_effort, aes(x = date, y = fct_rev(factor(location)))) +
  geom_tile(data = filter(drone_effort, n_redds > 0), aes(fill = n_redds), width = 1.6, height = 0.85) +
  geom_point(data = filter(drone_effort, n_redds == 0), shape = 4, size = 1.6, color = "#c0392b", stroke = 0.8) +
  scale_fill_viridis_c(trans = "log10", name = "Redds", option = "mako", direction = -1) +
  facet_grid(channel_location ~ year, scales = "free", space = "free") +
  labs(
    title = "Drone survey effort by location and date",
    subtitle = "Filled = redds found; X = flown, no redds found; blank = no flight recorded",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "top", strip.text = element_text(face = "bold"))

ggsave(file.path(diagnostics_dir, "drone_survey_effort.png"), p_effort, width = 12, height = 10, dpi = 110)

# drone and ground redds by published EDI location. Where both methods cover
# the same site the same physical redd can be recorded twice, so these are NOT
# a combined census - this just shows where the two overlap.
redds_by_method <- bind_rows(
  drone_redd_clean |> filter(n_redds > 0) |> group_by(edi_location) |> summarise(n = sum(n_redds), .groups = "drop") |> mutate(method = "drone"),
  ground_redd_clean |> count(edi_location) |> mutate(method = "ground")
) |>
  mutate(edi_location = fct_reorder(edi_location, n, .fun = sum))

p_methods <- ggplot(redds_by_method, aes(x = n, y = edi_location, color = method)) +
  geom_point(size = 2.5, alpha = 0.9) +
  scale_x_log10() +
  scale_color_manual(values = c(drone = "#1f4e9c", ground = "#e8590c"), name = NULL) +
  labs(
    title = "Redds by published EDI location: drone vs ground survey",
    subtitle = "Sites with both a drone and a ground point are covered by both methods,\nso the same redd can appear in both",
    x = "Number of redds (log scale)", y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top")

ggsave(file.path(diagnostics_dir, "redds_by_edi_location_and_method.png"), p_methods, width = 8, height = 9, dpi = 110)
