# rivermile-crosswalk-map.R
#
# ONE-OFF exploratory script (not part of the ingest/clean/qc pipeline).
#
# Purpose: check whether the "River Miles.kmz" file can be used to assign river
# miles to the seine locations that the Subsite Table crosswalk couldn't
# resolve. Builds a leaflet map of the KMZ river mile markers together with the
# unresolved locations that have coordinates, and reports the nearest river
# mile to each as a *suggestion* to be eyeballed on the map before trusting it.
#
# Output: data/clean/diagnostics/rivermile_crosswalk_map.html

library(tidyverse)
library(sf)
library(leaflet)
library(htmlwidgets)

# ── river mile markers from the KMZ ───────────────────────────────────────

# a .kmz is a zipped .kml; unzip to a temp dir rather than alongside the raw data
kmz_path <- here::here("edi-seine", "data", "raw", "River Miles.kmz")
kmz_dir  <- file.path(tempdir(), "river_miles_kmz")
unzip(kmz_path, exdir = kmz_dir)

# the KML's <name> element is the river mile itself ("0", "1", ... "67"), so
# there's no need to parse the HTML <description> table
river_mile_pts <- st_read(file.path(kmz_dir, "doc.kml"), quiet = TRUE) |>
  st_zm() |>
  transmute(river_mile = as.numeric(Name)) |>
  arrange(river_mile)

# rough river centerline, purely to make the map readable - the KMZ is points
# at ~1 mile spacing, so this is a coarse approximation, not the real thalweg
river_line <- river_mile_pts |>
  st_combine() |>
  st_cast("LINESTRING") |>
  st_sf(geometry = _)

# ── locations that need a river mile ──────────────────────────────────────

# These are the unresolved locations flagged for follow-up. Note "Unit 26A" and
# "24th St. Levee OWA" are two separate locations (they appear on one line in
# the original list).
target_locations <- c(
  "Mulberry Beach RR - Downstream",
  "250 yards below Honcut Confluence",
  "Below Long Glide",
  "Downstream Clay Banks RR",
  "Pollywog Beach",
  "Clay Banks upstream backwater RL",
  "Ellis Road Beach",
  "Downstream Bum Beach",
  "bend backwater (562)",
  "Unit 26A",
  "24th St. Levee OWA"
)

# Coordinates are NOT in all_seine_clean (lat/long were dropped from the
# published dataset), so read them straight from the accdb Location_LU table.
db_path <- here::here("edi-seine", "data", "raw", "FR Seining_2015_ 2025.accdb")
location_lu <- system2("mdb-export", args = c(shQuote(db_path), shQuote("Location_LU")),
                       stdout = TRUE) |>
  paste(collapse = "\n") |>
  I() |>
  read_csv(show_col_types = FALSE) |>
  janitor::clean_names()

# The columns are named "UTM Easting"/"UTM Northing" but for these rows they
# actually hold decimal degrees. At least one row (24th St. Levee OWA) has
# latitude and longitude swapped with the longitude's negative sign dropped.
# Detect that by range rather than hardcoding the site, so the same repair
# applies to any other row with the problem. The Feather River sits entirely
# at lon ~-121.5 to -121.7 and lat ~38.8 to 39.6, so the two are unambiguous.
unresolved_sites <- location_lu |>
  filter(site_name %in% target_locations) |>
  mutate(
    is_swapped = abs(utm_easting)  > 38  & abs(utm_easting)  < 41 &
                 abs(utm_northing) > 120 & abs(utm_northing) < 123,
    longitude  = if_else(is_swapped, -abs(utm_northing), -abs(utm_easting)),
    latitude   = if_else(is_swapped,  abs(utm_easting),   abs(utm_northing)),
    coord_repair = case_when(
      is_swapped      ~ "lat/lon swapped, lon sign restored",
      utm_easting > 0 ~ "lon sign restored",
      TRUE            ~ "as recorded"
    )
  ) |>
  filter(!is.na(longitude), !is.na(latitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

# which of the requested locations had no coordinates to plot?
missing_coords <- setdiff(target_locations, unresolved_sites$site_name)

# ── nearest river mile (a suggestion, not an assignment) ──────────────────

nearest_idx <- st_nearest_feature(unresolved_sites, river_mile_pts)

unresolved_sites <- unresolved_sites |>
  mutate(
    nearest_river_mile = river_mile_pts$river_mile[nearest_idx],
    dist_to_rm_m = as.numeric(
      st_distance(unresolved_sites, river_mile_pts[nearest_idx, ], by_element = TRUE)
    )
  )

cat("\n=== Suggested river miles (verify against the map before using) ===\n")
unresolved_sites |>
  st_drop_geometry() |>
  select(site_name, longitude, latitude, nearest_river_mile, dist_to_rm_m, coord_repair) |>
  mutate(dist_to_rm_m = round(dist_to_rm_m)) |>
  arrange(nearest_river_mile) |>
  print(n = Inf)

if (length(missing_coords) > 0) {
  cat("\n=== No coordinates available - cannot be mapped ===\n")
  cat(paste0("  - ", missing_coords, collapse = "\n"), "\n")
  cat("(these are 1997-2001 records; that era never recorded lat/long)\n")
}

# ── map ───────────────────────────────────────────────────────────────────

rm_map <- leaflet() |>
  addProviderTiles("Esri.WorldImagery", group = "Satellite") |>
  addProviderTiles("OpenStreetMap", group = "Street") |>
  addPolylines(
    data = river_line, color = "#52514e", weight = 2, opacity = 0.6,
    group = "River (RM centerline)"
  ) |>
  addCircleMarkers(
    data = river_mile_pts,
    radius = 4, stroke = FALSE, fillOpacity = 0.85, fillColor = "#2a78d6",
    label = ~paste("RM", river_mile),
    popup = ~paste0("<b>River Mile ", river_mile, "</b>"),
    group = "River mile markers"
  ) |>
  addCircleMarkers(
    data = unresolved_sites,
    radius = 7, stroke = TRUE, color = "#ffffff", weight = 1.5,
    fillOpacity = 0.9, fillColor = "#eb6834",
    label = ~site_name,
    popup = ~paste0(
      "<b>", site_name, "</b><br>",
      "Nearest river mile: <b>", nearest_river_mile, "</b><br>",
      "Distance to that marker: ", round(dist_to_rm_m), " m<br>",
      "Coords: ", round(latitude, 5), ", ", round(longitude, 5), "<br>",
      "<i>", coord_repair, "</i>"
    ),
    group = "Unresolved locations"
  ) |>
  addLayersControl(
    baseGroups = c("Satellite", "Street"),
    overlayGroups = c("River (RM centerline)", "River mile markers", "Unresolved locations"),
    options = layersControlOptions(collapsed = FALSE)
  ) |>
  addLegend(
    position = "bottomright",
    colors = c("#2a78d6", "#eb6834"),
    labels = c("River mile marker", "Location needing a river mile"),
    title = "Legend"
  )

out_html <- here::here("edi-seine", "data", "clean", "diagnostics",
                       "rivermile_crosswalk_map.html")
saveWidget(rm_map, out_html, selfcontained = TRUE)
cat("\nMap written to:", out_html, "\n")
