library(ggplot2)

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


filter_feather_cover <-
  feather_cover |>
  filter(location == "aleck riffle") |>
 # filter(location_table_id == '2001-03-14 (location id: 11)') |>
  mutate(transect_code = as.factor(transect_code)) |>
  group_by(transect_code, cover_type, fish_presence, location_table_id) |>
  summarize(percent_cover = if(all(is.na(percent_cover))) NA_real_
            else(mean(percent_cover, na.rm = T)))


ggplot(data = filter_feather_cover,
       aes(x = cover_type, y = transect_code, fill = percent_cover)) +
  geom_tile(aes(fill = percent_cover), color = "white", size = 0.5) +
  geom_tile(
    data = filter_feather_cover,
    aes(color = factor(fish_presence)),
    fill = NA,
    size = 0.5
  ) +
  scale_fill_gradient(low = "#D5D5D3", high = "#02401B", name = "Percent Cover") +
  scale_color_manual(values = c("darkred", "darkgrey"), name = "Fish Presence", labels = c("Yes", "No")) +
  labs(
    x = "",
    y = "Microhabitat Unit"
  ) +
  theme_minimal() +
  theme(
    axis.title = element_text(size = 16),
    axis.text = element_text(size = 10, face = "bold"),
    axis.text.x = element_text(angle = 30, hjust = 1),
    legend.title = element_text(size = 14, face = "bold"),
    legend.text = element_text(size = 10, face = "bold"),
    legend.position = "top"
  ) +
  facet_wrap(~location_table_id)
