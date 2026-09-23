library(tidyverse)
library(sf)
library(leaflet)
library(htmlwidgets)

drone_survey_dir <- here::here("edi-redd", "drone-survey")
clean_data_dir   <- file.path(drone_survey_dir, "data", "clean")

drone_redd_clean_all <- read_csv(file.path(clean_data_dir, "drone_redd_clean.csv"), show_col_types = FALSE)

# flight-schedule "surveyed, zero redds" rows (n_redds == 0) have no
# coordinates by design (see clean-data.R) and can't be plotted as points;
# they're still included in the summary charts below via sum(n_redds), which
# correctly contributes 0
redd_pts <- drone_redd_clean_all |>
  filter(!is.na(longitude), !is.na(latitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

flight_routes <- st_read(file.path(clean_data_dir, "drone_flight_routes_compiled.shp"), quiet = TRUE)

# Redd points that sat inside more than one mission's buffer and had to be
# resolved to a single mission (nearest distance, or an exact mission-name
# match overriding distance) - see clean-data.R. Shown as their own map layer
# below so each decision can be reviewed against its actual location.
diagnostics_dir <- file.path(clean_data_dir, "diagnostics")
ambiguous_path  <- file.path(diagnostics_dir, "ambiguous_mission_matches.csv")
ambiguous_pts <- if (file.exists(ambiguous_path)) {
  read_csv(ambiguous_path, show_col_types = FALSE) |>
    st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
} else {
  NULL
}

# collapse the mission x location rows back to one polygon per distinct
# geometry (a mission spanning several locations still has one shape) so the
# map draws each flight route once, with all of its matched locations in the
# popup rather than the same outline stacked on top of itself
flight_routes_map <- flight_routes |>
  group_by(mission) |>
  summarise(
    locations = paste(sort(unique(location)), collapse = ", "),
    n_redds = sum(n_redds, na.rm = TRUE),
    .groups = "drop"
  )

channel_pal <- colorFactor(c("#2a78d6", "#eb6834"), domain = c("HFC", "LFC"))
route_color <- "black"
resolution_pal <- colorFactor(c("#eda100", "#1baf7a", "#9085e9"),
                              domain = c("exact name match", "location starts with mission name", "nearest distance"))

# OpenStreetMap's own tile servers block requests with no Referer header,
# which is exactly what happens when this map is opened as a local file or an
# email attachment rather than served from a website ("access blocked" on the
# Street layer). Esri's street basemap uses the same tile infrastructure as
# the Satellite layer below, which doesn't have that restriction.
drone_map <- leaflet() |>
  addProviderTiles("Esri.WorldStreetMap", group = "Street") |>
  addProviderTiles("Esri.WorldImagery", group = "Satellite") |>
  addPolygons(
    data = flight_routes_map,
    color = route_color,
    weight = 2,
    fillOpacity = 0.08,
    label = ~mission,
    popup = ~paste0(
      "<b>Mission:</b> ", mission, "<br>",
      "<b>Location(s):</b> ", locations, "<br>",
      "<b>Redds inside:</b> ", n_redds
    ),
    group = "Flight routes"
  ) |>
  addCircleMarkers(
    data = filter(redd_pts, channel_location == "HFC"),
    radius = 4, stroke = FALSE, fillOpacity = 0.8,
    fillColor = ~channel_pal(channel_location),
    popup = ~paste0("<b>", location, "</b><br>", date, "<br>", channel_location),
    group = "HFC redds"
  ) |>
  addCircleMarkers(
    data = filter(redd_pts, channel_location == "LFC"),
    radius = 4, stroke = FALSE, fillOpacity = 0.8,
    fillColor = ~channel_pal(channel_location),
    popup = ~paste0("<b>", location, "</b><br>", date, "<br>", channel_location),
    group = "LFC redds"
  )

# Points that intersected more than one mission's buffer, shown so each
# resolution can be reviewed - gold for an exact mission-name match, teal
# where the location is a named sub-area of the mission (e.g. "G95 West
# Bottom" under mission "G95 West"), purple where nearest distance decided
# it outright with no name-based rule applying.
if (!is.null(ambiguous_pts)) {
  drone_map <- drone_map |>
    addCircleMarkers(
      data = ambiguous_pts,
      radius = 9, stroke = TRUE, color = "#000000", weight = 1.5,
      fillOpacity = 0.95, fillColor = ~resolution_pal(resolved_by),
      label = ~paste0(location, " -> ", assigned_mission, " (", resolved_by, ")"),
      popup = ~paste0(
        "<b>Location:</b> ", location, "<br>",
        "<b>Assigned mission:</b> ", assigned_mission, "<br>",
        "<b>Resolved by:</b> ", resolved_by, "<br>",
        "<b>All candidates:</b> ", all_candidates
      ),
      group = "Ambiguous mission matches (review)"
    )
}

overlay_groups <- c("Flight routes", "HFC redds", "LFC redds")
legend_colors  <- c("#2a78d6", "#eb6834", "black")
legend_labels  <- c("HFC redd", "LFC redd", "flight route")

if (!is.null(ambiguous_pts)) {
  overlay_groups <- c(overlay_groups, "Ambiguous mission matches (review)")
  legend_colors  <- c(legend_colors, "#eda100", "#1baf7a", "#9085e9")
  legend_labels  <- c(legend_labels, "Ambiguous: exact name match", "Ambiguous: location starts with mission name", "Ambiguous: nearest distance")
}

drone_map <- drone_map |>
  addLayersControl(
    baseGroups = c( "Street", "Satellite"),
    overlayGroups = overlay_groups,
    options = layersControlOptions(collapsed = FALSE)
  ) |>
  addLegend(
    position = "bottomright",
    colors = legend_colors,
    labels = legend_labels,
    title = "Legend"
  )

drone_map

# selfcontained = TRUE inlines all JS/CSS as data URIs into the one .html file
# (verified: the saved file has zero references to a "_files" folder), so it
# opens correctly as a standalone email attachment with no companion files
# needed - only the live map tiles (OpenStreetMap/Esri) need an internet
# connection when the recipient opens it. saveWidget still leaves behind a
# "_files" support folder as build scratch even in selfcontained mode; it's
# not referenced by the html and is removed here so it isn't mistaken for a
# required companion file.
map_path <- file.path(diagnostics_dir, "drone_flight_redd_map.html")
saveWidget(drone_map, map_path, selfcontained = TRUE)
unlink(file.path(diagnostics_dir, "drone_flight_redd_map_files"), recursive = TRUE)

### Summary charts ----

channel_colors <- c(HFC = "#2a78d6", LFC = "#eb6834")

redds_by_location <- drone_redd_clean_all |>
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

ggsave(file.path(diagnostics_dir, "redds_by_location.png"), p_by_location, width = 8, height = 10, dpi = 150)

redds_by_date <- drone_redd_clean_all |>
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

ggsave(file.path(diagnostics_dir, "redds_by_date.png"), p_by_date, width = 9, height = 5, dpi = 150)
