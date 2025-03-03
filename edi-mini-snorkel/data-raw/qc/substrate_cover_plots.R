# QUICK ANALYSIS 
source("data-raw/qc_mini_snorkel_data.Rmd")
colors_small <- c( "#9A8822", "#798E87", "#5B1A18", "#972D15", "#DC863B", "#AA9486")

substrate_plot <- joined_fish_obs |> 
  arrange(river_mile) |> 
  mutate(obs_id = 1:nrow(joined_fish_obs)) |> 
  select(obs_id, 
         percent_fine_substrate,
         percent_sand_substrate,
         percent_small_gravel_substrate,
         percent_large_gravel_substrate,
         percent_cobble_substrate,
         percent_boulder_substrate,
         count) |> 
  pivot_longer(cols = percent_fine_substrate:percent_boulder_substrate, 
               names_to = "substrate_type", values_to = "percent") |> 
  ggplot(aes(x = obs_id, y = percent, fill = substrate_type)) +
  geom_col() +
  scale_fill_manual(values = colors_small) +
  theme_minimal() +
  theme(legend.position = "bottom") +
  geom_point(aes(x = obs_id, y = 1, size = count), color = "#02401B", fill = "#02401B")
plotly::ggplotly(substrate_plot)


inchannel_cover_plot <- joined_fish_obs |> 
  arrange(river_mile) |> 
  mutate(obs_id = 1:nrow(joined_fish_obs)) |> 
  select(obs_id, 
         percent_no_cover_inchannel,
         percent_small_woody_cover_inchannel,
         percent_large_woody_cover_inchannel,
         percent_submerged_aquatic_veg_inchannel,
         count) |> 
  pivot_longer(cols = percent_no_cover_inchannel:percent_submerged_aquatic_veg_inchannel, 
               names_to = "inchannel_cover_type", values_to = "percent") |> 
  ggplot(aes(x = obs_id, y = percent, fill = inchannel_cover_type)) +
  geom_col() +
  scale_fill_manual(values = colors_small[4:7]) +
  theme_minimal() +
  theme(legend.position = "bottom") +
  geom_point(aes(x = obs_id, y = 1, size = count), color = "#02401B", fill = "#02401B")
plotly::ggplotly(inchannel_cover_plot)


overhead_cover_plot <- joined_fish_obs |> 
  arrange(location) |> 
  mutate(obs_id = 1:nrow(joined_fish_obs)) |> 
  select(obs_id, 
         percent_undercut_bank,
         percent_no_cover_overhead,
         percent_cover_half_meter_overhead,
         percent_cover_more_than_half_meter_overhead,
         count,
         location) |> 
  pivot_longer(cols = percent_undercut_bank:percent_cover_more_than_half_meter_overhead, 
               names_to = "overhead_cover_type", values_to = "percent") |> 
  ggplot(aes(x = obs_id, y = percent, fill = overhead_cover_type)) +
  geom_col() +
  scale_fill_manual(values = colors_small[4:7]) +
  theme_minimal() +
  theme(legend.position = "bottom") +
  geom_point(aes(x = obs_id, y = 1, size = count), color = "#02401B", fill = "#02401B")
  # +
  # facet_wrap(~location, scales = "free_x")

plotly::ggplotly(overhead_cover_plot)
