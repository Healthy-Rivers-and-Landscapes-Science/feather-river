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

diagnostics_dir <- file.path(clean_data_dir, "diagnostics")

# the flight route shapefile is pure geometry keyed by `mission` (no location
# or redd count - see clean-data.R), so it's plotted as is
flight_routes_map <- flight_routes

# Ground (walking) redd survey location polygons - the spawning-location
# boundaries Chris used to assign each drone redd to a `location` (not the
# flight route mission boundaries). Each gdb layer is one location polygon, so
# they're read into a single sf with the layer name as `location`.
gdb_path <- here::here("edi-redd", "data-raw", "shapefiles", "b105_redd_survey_locations_maps_2021.gdb")

ground_survey_locations <- st_layers(gdb_path)$name |>
  map(function(layer_name) {
    st_read(dsn = gdb_path, layer = layer_name, quiet = TRUE) |>
      st_transform(4326) |>
      st_zm(drop = TRUE, what = "ZM") |>
      transmute(location = layer_name)
  }) |>
  list_rbind() |>
  st_as_sf()

ground_color <- "#1a7f4b"

channel_pal <- colorFactor(c("#2a78d6", "#eb6834"), domain = c("HFC", "LFC"))
route_color <- "black"

### Drone location name -> published EDI location name QC ----

# Goal: map every drone `location` to a location name in the published ground
# survey EDI package (edi.1802: data/survey_site_area.csv and
# data/redd_observations.csv - lowercase, no spaces, e.g. "uppercottonwood").
# The ground survey location boundaries (gdb layers) are named the same way,
# so each redd's EDI name is also checked against its boundary. The result goes
# in drone_to_edi_location_qc.csv and in each redd's popup on the map below.
#
# The crosswalk is the hand-editable file
# data/crosswalk/drone_to_edi_location_crosswalk.csv (one row per drone
# location; `basis` records exact name match vs a proposed match awaiting
# confirmation). clean-data.R applies it to add `edi_location`; this script just
# checks it against the boundaries. A drone location missing from the file is
# flagged UNMATCHED, never guessed.

norm_name <- function(x) str_replace_all(str_to_lower(x), "[^a-z0-9]", "")

edi_sites <- union(
  read_csv(here::here("edi-redd", "data", "survey_site_area.csv"), show_col_types = FALSE)$location,
  read_csv(here::here("edi-redd", "data", "redd_observations.csv"), col_select = location, show_col_types = FALSE)$location
) |> unique()

crosswalk <- drone_redd_clean_all |>
  distinct(drone_location = location) |>
  left_join(
    read_csv(file.path(drone_survey_dir, "data", "crosswalk", "drone_to_edi_location_crosswalk.csv"),
             show_col_types = FALSE),
    by = "drone_location"
  ) |>
  mutate(basis = if_else(is.na(edi_location), "UNMATCHED", basis)) |>
  select(drone_location, edi_location, basis, note)

if (any(crosswalk$basis == "UNMATCHED")) {
  warning("drone location(s) with no EDI name in the crosswalk: ", paste(crosswalk$drone_location[crosswalk$basis == "UNMATCHED"], collapse = ", "))
}
if (any(!na.omit(crosswalk$edi_location) %in% edi_sites)) {
  warning("crosswalk edi_location(s) not found in the published EDI data: ",
          paste(setdiff(na.omit(crosswalk$edi_location), edi_sites), collapse = ", "))
}

# ground survey boundaries are keyed by their normalized layer name, which
# equals the EDI location name
ground_poly <- ground_survey_locations |>
  rename(polygon_name = location) |>
  mutate(key = norm_name(polygon_name))

polys_m <- st_transform(ground_poly, 3310)

# (drone_redd_clean.csv already carries edi_location from clean-data.R; it's
# re-derived here from the crosswalk file so this check still works if the
# crosswalk is edited before clean-data.R is re-run)
redd_pts_xw <- redd_pts |>
  select(-any_of("edi_location")) |>
  left_join(crosswalk |> select(drone_location, edi_location, basis), by = c("location" = "drone_location"))

pts_m   <- st_transform(redd_pts_xw, 3310)
own_idx <- match(redd_pts_xw$edi_location, ground_poly$key)  # NA when the EDI site has no boundary polygon
hits    <- st_intersects(pts_m, polys_m)

own_dist <- rep(NA_real_, nrow(pts_m))
has_own  <- which(!is.na(own_idx))
own_dist[has_own] <- as.numeric(st_distance(pts_m[has_own, ], polys_m[own_idx[has_own], ], by_element = TRUE))

position_levels <- c(
  "inside own boundary", "inside a different boundary",
  "outside all boundaries", "EDI site has no boundary polygon"
)

redd_pts_xw <- redd_pts_xw |>
  mutate(
    contained_in = map_chr(hits, \(i) paste(ground_poly$polygon_name[i], collapse = " + ")),
    own_dist_m   = own_dist,
    position = case_when(
      is.na(own_idx)                                    ~ "EDI site has no boundary polygon",
      map2_lgl(hits, own_idx, \(h, o) o %in% h)         ~ "inside own boundary",
      contained_in != ""                                ~ "inside a different boundary",
      TRUE                                              ~ "outside all boundaries"
    ),
    position = factor(position, levels = position_levels)
  )

# per drone location evidence behind each crosswalk row
crosswalk_qc <- crosswalk |>
  left_join(
    redd_pts_xw |> st_drop_geometry() |>
      group_by(drone_location = location) |>
      summarise(
        n_points = n(),
        n_inside_own = sum(position == "inside own boundary"),
        n_inside_other = sum(position == "inside a different boundary"),
        n_outside_all = sum(position == "outside all boundaries"),
        n_no_polygon = sum(position == "EDI site has no boundary polygon"),
        most_common_other_boundary = {
          o <- contained_in[position == "inside a different boundary"]
          if (length(o) == 0) NA_character_ else names(sort(table(o), decreasing = TRUE))[1]
        },
        .groups = "drop"
      ),
    by = "drone_location"
  ) |>
  mutate(
    across(starts_with("n_"), \(x) replace_na(x, 0L)),
    edi_site_has_polygon = edi_location %in% ground_poly$key
  ) |>
  arrange(basis != "UNMATCHED", str_detect(basis, "exact"), drone_location)

write_csv(crosswalk_qc, file.path(diagnostics_dir, "drone_to_edi_location_qc.csv"))

# which drone location name(s) map to each ground boundary's EDI name (shown
# in the boundary popup)
mapped_to <- crosswalk |>
  filter(!is.na(edi_location)) |>
  group_by(key = edi_location) |>
  summarise(drone_names = paste(sort(drone_location), collapse = ", "), .groups = "drop")

poly_map <- ground_poly |>
  left_join(mapped_to, by = "key") |>
  mutate(has_drone_name = !is.na(drone_names))

### Map: ground survey boundaries, drone flight routes, drone redds ----

point_popup <- ~paste0(
  "<b>Drone redd location name:</b> ", location, "<br>",
  "<b>Published EDI location name:</b> ", edi_location, "<br>",
  date, " (", channel_location, ")<br>",
  position,
  if_else(contained_in != "", paste0("<br>inside boundary: ", contained_in), ""),
  if_else(!is.na(own_dist_m) & own_dist_m > 0, paste0("<br>", round(own_dist_m, 1), " m from its own boundary"), "")
)

# OpenStreetMap's own tile servers block requests with no Referer header,
# which is exactly what happens when this map is opened as a local file or an
# email attachment rather than served from a website ("access blocked" on the
# Street layer). Esri's street basemap uses the same tile infrastructure as
# the Satellite layer below, which doesn't have that restriction.
drone_map <- leaflet() |>
  addProviderTiles("Esri.WorldStreetMap", group = "Street") |>
  addProviderTiles("Esri.WorldImagery", group = "Satellite") |>
  # added first so the flight routes and redd points draw on top of it
  addPolygons(
    data = poly_map,
    color = ground_color, fillColor = ground_color, weight = 2, fillOpacity = 0.25,
    label = ~polygon_name,
    popup = ~paste0(
      "<b>Published EDI location name:</b> ", key, "<br>",
      "<b>Drone redd location name(s):</b> ", replace_na(drone_names, "none")
    ),
    group = "Ground survey locations"
  ) |>
  addPolygons(
    data = flight_routes_map,
    color = route_color, weight = 2, fillOpacity = 0.08,
    label = ~mission,
    popup = ~paste0("<b>Flight route (mission):</b> ", mission),
    group = "Flight routes"
  ) |>
  addCircleMarkers(
    data = redd_pts_xw,
    radius = 4, stroke = FALSE, fillOpacity = 0.8,
    fillColor = ~channel_pal(channel_location),
    popup = point_popup,
    group = "Drone redds"
  ) |>
  addLayersControl(
    baseGroups = c("Street", "Satellite"),
    overlayGroups = c("Ground survey locations", "Flight routes", "Drone redds"),
    options = layersControlOptions(collapsed = FALSE)
  ) |>
  addLegend(
    position = "bottomright",
    colors = c("#2a78d6", "#eb6834", "black", ground_color),
    labels = c("HFC redd", "LFC redd", "flight route", "ground survey location"),
    title = "Legend"
  )

drone_map

# selfcontained = TRUE inlines all JS/CSS as data URIs into the one .html file
# (verified: the saved file has zero references to a "_files" folder), so it
# opens correctly as a standalone email attachment with no companion files
# needed - only the live map tiles (Esri) need an internet connection when the
# recipient opens it. saveWidget still leaves behind a "_files" support folder
# as build scratch even in selfcontained mode; it's not referenced by the html
# and is removed here so it isn't mistaken for a required companion file.
map_path <- file.path(diagnostics_dir, "drone_flight_redd_map.html")
saveWidget(drone_map, map_path, selfcontained = TRUE)
unlink(file.path(diagnostics_dir, "drone_flight_redd_map_files"), recursive = TRUE)

print(count(crosswalk_qc, basis))
print(redd_pts_xw |> st_drop_geometry() |> count(position))
