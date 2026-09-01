# Script to QC the cleaned dataset
library(tidyverse)

all_seine_clean <- read_csv(
  here::here("edi-seine", "data", "clean", "all_seine_clean.csv"),
  show_col_types = FALSE
)

# `source` is dropped in clean-data.R's final select, but the three source
# datasets differ enough (units, which depth fields exist, which columns are
# populated at all) that most QC only makes sense per-era. Rederive it from year.
qc_data <- all_seine_clean |>
  mutate(
    era = case_when(
      year <= 2001 ~ "1997-2001",
      year <= 2014 ~ "2008-2014",
      !is.na(year) ~ "2015-2025",
      TRUE         ~ NA_character_
    )
  )

# Continuous variables to profile. depth_1/depth_2 only exist for 1997-2001
# (point depths at full distance out / closest to shore) and depth_avg only
# for 2008 onward - they are deliberately NOT combined, so expect each to be
# NA for the eras that don't record it.
continuous_vars <- c(
  "water_temp", "secchi", "fork_length", "weight",
  "depth_1", "depth_2", "depth_avg",
  "length", "width", "distance_out", "sample_area",
  "count", "river_mile"
)

### High level QC flags ----

qc_flags <- qc_data |>
  mutate(
    row_id = row_number(),

    # missingness on fields every record should have
    missing_date     = is.na(date),
    missing_location = is.na(location) | location == "",

    # seine surveys sample wadable habitat by hand/beach seine - anything
    # much deeper than a few meters is almost certainly a data entry error.
    # Checked across all three depth columns since they're era-specific.
    invalid_depth = pmap_lgl(
      list(depth_1, depth_2, depth_avg),
      \(d1, d2, da) any(c(d1, d2, da) < 0 | c(d1, d2, da) > 10, na.rm = TRUE)
    ),

    # plausible Feather River water temperature range (river never freezes
    # or boils); the -17.8 (F->C of a 0 sentinel) and 147 cases are corrected
    # in clean-data.R, so this should now come back clean
    invalid_water_temp = !is.na(water_temp) & (water_temp < -2 | water_temp > 35),

    # a recorded fork length of 0mm isn't a real measurement - these are plus
    # counts and are set to NA in clean-data.R, so this should now be clean
    invalid_fork_length = !is.na(fork_length) & fork_length <= 0,

    # weight should be positive when recorded
    invalid_weight = !is.na(weight) & weight <= 0,

    # seine haul geometry can't be zero or negative when recorded
    invalid_length      = !is.na(length) & length <= 0,
    invalid_width       = !is.na(width) & width <= 0,
    invalid_sample_area = !is.na(sample_area) & sample_area <= 0,

    # secchi is a depth reading, so non-negative
    invalid_secchi = !is.na(secchi) & secchi < 0,

    # channel should only ever be the two named channels (or NA pre-2015)
    unexpected_channel = !is.na(channel) & !channel %in% c("HFC", "LFC"),

    # gear_type should be exactly SEIN post-cleaning (NETS/EF_SE/EF-SE are
    # removed in clean-data.R)
    unexpected_gear_type = gear_type != "SEIN",

    # a species record with a non-positive count isn't meaningful
    invalid_count = !is.na(species) & !is.na(count) & count <= 0,

    # dates outside the range the raw data can possibly cover
    date_out_of_range = !missing_date & (date < as.Date("1997-01-01") | date > Sys.Date()),

    # location never resolved to a river mile (see the manual crosswalk in
    # clean-data.R and diagnostics/river_mile_unresolved.csv)
    missing_river_mile = is.na(river_mile)
  )

flag_cols <- c(
  "missing_date", "missing_location",
  "invalid_depth", "invalid_water_temp", "invalid_fork_length", "invalid_weight",
  "invalid_length", "invalid_width", "invalid_sample_area", "invalid_secchi",
  "unexpected_channel", "unexpected_gear_type", "invalid_count",
  "date_out_of_range", "missing_river_mile"
)

qc_summary <- qc_flags |>
  summarise(n_rows = n(), across(all_of(flag_cols), sum))

print(glimpse(qc_summary))

# same counts broken out by era, since most of these are era-specific
qc_summary_by_era <- qc_flags |>
  group_by(era) |>
  summarise(n_rows = n(), across(all_of(flag_cols), sum), .groups = "drop")

print(qc_summary_by_era)

walk(flag_cols, \(f) {
  n <- qc_summary[[f]]
  if (n > 0) warning(n, " row(s) flagged: ", f)
})

# Exact duplicate rows - INFORMATIONAL, not an error. Each row is an individual
# fish record, so two fish of the same species with the same fork length in the
# same haul are legitimately identical once the per-fish `id` is dropped in
# clean-data.R's final select. Counted on the published columns rather than on
# qc_flags, whose row_id = row_number() makes every row unique by construction
# (which is why this previously always reported 0).
n_duplicate_rows <- sum(duplicated(all_seine_clean))
cat("\nExact duplicate rows (expected - see note in script):", n_duplicate_rows,
    sprintf("(%.1f%% of rows)\n", 100 * n_duplicate_rows / nrow(all_seine_clean)))

# more detail on flagged issues:
qc_flags |> filter(invalid_depth) |> select(date, sample_id, location, depth_avg)
qc_flags |> filter(missing_river_mile) |> count(location, sort = TRUE)
all_seine_clean |> pull(channel) |> unique()

qc_flags |>
  filter(if_any(all_of(flag_cols))) |>
  write_csv(here::here("edi-seine", "data", "clean", "diagnostics", "qc_flagged_rows.csv"))

### Continuous variable plots ----

fig_dir <- here::here("edi-seine", "data", "clean", "diagnostics", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

era_colors <- c("1997-2001" = "#2a78d6", "2008-2014" = "#eb6834", "2015-2025" = "#1baf7a")

continuous_long <- qc_data |>
  select(date, year, era, all_of(continuous_vars)) |>
  pivot_longer(all_of(continuous_vars), names_to = "variable", values_to = "value") |>
  filter(!is.na(value))

# 1. Distribution of each continuous variable. Free scales because the
# variables are on wildly different units (degrees C vs mm vs sq meters);
# this is the view that surfaces outliers and impossible values.
p_dist <- ggplot(continuous_long, aes(x = value)) +
  geom_histogram(bins = 50, fill = "#2a78d6") +
  facet_wrap(~variable, scales = "free", ncol = 3) +
  labs(
    title = "Distribution of continuous variables",
    subtitle = "Free x and y scales - look for impossible values and long right tails",
    x = NULL, y = "Count"
  ) +
  theme_minimal(base_size = 11)

ggsave(file.path(fig_dir, "qc_continuous_distributions.png"), p_dist,
       width = 11, height = 10, dpi = 150)

# 2. Same distributions split by era. Catches era-specific problems: unit
# changes, sentinel values, and fields only collected in some eras.
p_dist_era <- ggplot(continuous_long, aes(x = value, fill = era)) +
  geom_histogram(bins = 40, position = "identity", alpha = 0.65) +
  facet_wrap(~variable, scales = "free", ncol = 3) +
  scale_fill_manual(values = era_colors, name = NULL) +
  labs(
    title = "Distribution of continuous variables by source era",
    subtitle = "Gaps show fields a given era never recorded (e.g. depth_1/2 vs depth_avg)",
    x = NULL, y = "Count"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")

ggsave(file.path(fig_dir, "qc_continuous_distributions_by_era.png"), p_dist_era,
       width = 11, height = 10, dpi = 150)

# 3. Value over time. This is the view that catches step changes at era
# boundaries and one-off spikes that a histogram can hide.
p_time <- ggplot(continuous_long, aes(x = date, y = value, color = era)) +
  geom_point(alpha = 0.25, size = 0.5) +
  facet_wrap(~variable, scales = "free_y", ncol = 3) +
  scale_color_manual(values = era_colors, name = NULL) +
  labs(
    title = "Continuous variables over time",
    subtitle = "Look for step changes at era boundaries and isolated spikes",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top") +
  guides(color = guide_legend(override.aes = list(alpha = 1, size = 2)))

ggsave(file.path(fig_dir, "qc_continuous_over_time.png"), p_time,
       width = 12, height = 10, dpi = 150)

# 4. Boxplots by era - compact view of centre/spread/outliers per era.
p_box <- ggplot(continuous_long, aes(x = era, y = value, fill = era)) +
  geom_boxplot(outlier.alpha = 0.3, outlier.size = 0.6) +
  facet_wrap(~variable, scales = "free_y", ncol = 3) +
  scale_fill_manual(values = era_colors, guide = "none") +
  labs(
    title = "Continuous variables by source era",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

ggsave(file.path(fig_dir, "qc_continuous_by_era_boxplot.png"), p_box,
       width = 11, height = 10, dpi = 150)

# 5. Depth specifically - the three depth columns are era-specific and were
# deliberately left un-combined, so plot them together to confirm the coverage
# split is what's expected and to eyeball the remaining depth_avg outliers.
p_depth <- qc_data |>
  select(date, era, depth_1, depth_2, depth_avg) |>
  pivot_longer(c(depth_1, depth_2, depth_avg),
               names_to = "depth_field", values_to = "depth") |>
  filter(!is.na(depth)) |>
  ggplot(aes(x = date, y = depth, color = era)) +
  geom_point(alpha = 0.3, size = 0.6) +
  facet_wrap(~depth_field, ncol = 1) +
  scale_color_manual(values = era_colors, name = NULL) +
  labs(
    title = "Depth fields over time",
    subtitle = "depth_1/depth_2 are 1997-2001 point depths; depth_avg is 2008 onward",
    x = NULL, y = "Depth"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top") +
  guides(color = guide_legend(override.aes = list(alpha = 1, size = 2)))

ggsave(file.path(fig_dir, "qc_depth_fields.png"), p_depth,
       width = 10, height = 8, dpi = 150)

### Coverage summaries ----

cat("\nDate range:", as.character(range(all_seine_clean$date, na.rm = TRUE)), "\n")
cat("Years covered:", paste(range(all_seine_clean$year, na.rm = TRUE), collapse = "-"), "\n")

cat("\nRows by era:\n")
print(count(qc_data, era))

cat("\nRows by channel:\n")
print(count(all_seine_clean, channel, sort = TRUE))

cat("\nRows by gear_type:\n")
print(count(all_seine_clean, gear_type, sort = TRUE))

cat("\nRiver mile match rate (share of rows with a resolved river_mile):\n")
print(mean(!is.na(all_seine_clean$river_mile)))

cat("\nNon-NA coverage of each continuous variable, by era:\n")
print(
  qc_data |>
    group_by(era) |>
    summarise(across(all_of(continuous_vars), \(x) mean(!is.na(x))), .groups = "drop") |>
    mutate(across(all_of(continuous_vars), \(x) round(x, 3)))
)

cat("\nTop 20 species by row count:\n")
print(count(all_seine_clean, species, sort = TRUE), n = 20)
