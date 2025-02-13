# Test script for a new summary plot
# Plot summary of coverage on the map

# data code is same as in dashboard
library(tidyverse)
library(leaflet)
library(treemap)

colors_full <-  c("#9A8822", "#F5CDB4", "#F8AFA8", "#FDDDA0", "#74A089", #Royal 2
                  "#899DA4", "#C93312", "#DC863B", # royal 1 (- 3)
                  "#F1BB7B", "#FD6467", "#5B1A18", "#D67236",# Grand Budapest 1 (-4)
                  "#D8B70A", "#02401B", "#A2A475", # Cavalcanti 1
                  "#E6A0C4", "#C6CDF7", "#D8A499", "#7294D4", #Grand Budapest 2
                  "#9986A5", "#EAD3BF", "#AA9486", "#B6854D", "#798E87", # Isle of dogs 2 altered slightly
                  "#F3DF6C", "#CEAB07", "#D5D5D3", "#24281A", # Moonriese 1,
                  "#798E87", "#C27D38", "#CCC591", "#29211F", # moonrise 2
                  "#85D4E3", "#F4B5BD", "#9C964A", "#CDC08C", "#FAD77B" ) # moonrise 3

fish_pres_cols <- c('Yes' = "#E6A0C4", 'No' = "#D5D5D3")

colfunc <- colorRampPalette(c("#02401B", "white"))
gradient <- colfunc(100)

mini_locations_raw <- read_csv(here::here("mini-snorkel-app", "mini_locations_raw.csv"))
mini_fish_raw <- read_csv(here::here("mini-snorkel-app","mini_fish_raw.csv"))
# orders locations from upstream to downstream.
# TODO we are missing coordinates for some locations
location_order <- tibble(location = c("hatchery ditch", "hour bars", "hatchery riffle", "trailer park",
                                      "bedrock riffle", "steep riffle", "robinson riffle", "upper big hole",
                                      "lower big hole", "g95", "gridley riffle", "big bar", "goose riffle",
                                      "macfarland riffle", "shallow riffle", "herringer riffle", "junkyard riffle",
                                      "auditorium riffle", "eye side channel", "matthews riffle", "eye riffle",
                                      "lower hour", "aleck riffle", "weir riffle", "vance avenue",
                                      "big hole", "hour riffle", "cox riffle", "gateway riffle"),
                         order = c(2,19,1,5,
                                   4,9,8,15,
                                   16,17,23,21,20,
                                   22,25,26,24,
                                   3,11,6,12,
                                   18,7,10,13,
                                   14,NA,NA,NA))

feather_cover <- mini_fish_raw |>
  left_join(mini_locations_raw |>
              distinct(location_table_id, date, channel_location, location)) |>
  # create cover variables that are more consistent with strategic plan categories
  mutate(woody_debris = percent_small_woody_cover_inchannel + percent_large_woody_cover_inchannel,
         boulder = percent_boulder_substrate,
         cobble = percent_cobble_substrate,
         undercut_bank = percent_undercut_bank,
         aquatic_veg = percent_submerged_aquatic_veg_inchannel,
         overhanging_veg = percent_cover_half_meter_overhead + percent_cover_more_than_half_meter_overhead) |>
  select(micro_hab_data_tbl_id, location_table_id, transect_code, location,
         woody_debris:overhanging_veg, count, date) |>
  pivot_longer(cols = c(woody_debris, boulder, cobble, undercut_bank, aquatic_veg, overhanging_veg), names_to = "cover_type",
               values_to = "percent_cover") |>
  distinct() |>
  left_join(location_order) |>
  mutate(fish_presence = ifelse(count > 0, "Yes", "No")) |> select(-count) |>
  mutate(location_table_id = paste0(date, " (location id: ", location_table_id, ")")) |> glimpse()

summary_cover <- feather_cover |>
  mutate(month = month(date, label = T)) |>
  group_by(location, cover_type, order, fish_presence, month) |>
  summarize(percent_cover = mean(percent_cover, na.rm = T)) |>
  mutate(percent_cover = ifelse(is.na(percent_cover), 0, percent_cover))

# Create a test treemap image here that can be ploted on the map
png(here::here("mini-snorkel-app", "treemap_herr_riffle.png"))
treemap(filter(summary_cover, location == "herringer riffle"),
        index = "cover_type",
        vSize = "percent_cover")
dev.off()

locations_sf <- sf::st_as_sf(mini_locations_raw |>
                               distinct(location, .keep_all = T) |>
                               na.omit(), coords = c('longitude', 'latitude'))
# create the treemap icon
treemap_icons <- icons(
  iconUrl = "mini-snorkel-app/treemap_herr_riffle.png",
  iconWidth = 38, iconHeight = 38)

leaflet(locations_sf) |>
  addProviderTiles(providers$Esri.WorldImagery, group = "Aerial Imagery") |>
  addProviderTiles(providers$OpenStreetMap, group = "Street Map") |>
  addMarkers(icon = treemap_icons) |>
  # addCircleMarkers(layerId = ~location, #~location_table_id,
  #                  radius = 6,
  #                  fill = TRUE,
  #                  fillOpacity = 0.2,
  #                  opacity = 0.6) |>
  addLayersControl(
    baseGroups = c("Aerial Imagery", "Street Map"),
    position = "topleft",
    options = layersControlOptions(collapsed = FALSE)
  )


