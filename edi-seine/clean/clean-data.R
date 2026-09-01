# Script used to clean and wrangle the raw data into the clean data that will be published.
library(janitor)

source(here::here("edi-seine", "ingest", "read-data.R"))

# functions and helpers ---------------------------------------------------------------
organism_map   <- setNames(organism_code_lu$CommonName,   organism_code_lu$OrganismCode)
lifestage_map  <- setNames(
  salmonid_life_stage_lu[["Life stage"]],
  as.character(salmonid_life_stage_lu[["Life stage code"]])
)
substrate_map  <- setNames(hu_csubstrate_lu$Substrate,  as.character(hu_csubstrate_lu$SubstrateCode))
cover_map      <- setNames(hu_ccover_lu$Cover,          hu_ccover_lu$CoverCode)
unit_map       <- setNames(hu_cunit_lu$Unit,            hu_cunit_lu$UnitCode)
condition_map  <- setNames(tolower(condition_lu$Condition), as.character(condition_lu$ConditionCode))
weather_map    <- c(
  setNames(tolower(weather_lu$Weather), weather_lu$WeatherCode),
  "RAN" = "precipitation",   # code in older data; not in WeatherLU
  "FOG" = "foggy"
)

gear_map <- gear_lu |>
  clean_names() |>
  select(gear_num, gear_description, gear_type) |>
  rename(gear_size = gear_description)

decode_lifestage <- function(x) {
  case_when(
    x %in% c("P", "3")  ~ "parr",
    x %in% c("S", "5")  ~ "smolt",
    x == "X"             ~ "between parr and smolt",
    !is.na(x)            ~ coalesce(lifestage_map[as.character(x)], as.character(x))
  )
}

# Free-text `comments` are the only record of how many hauls/pulls were made
# in a survey (e.g. "2 pulls", "Two hauls", "1st pull ... 2nd pull ...",
# "#1 of 2 hauls"). Pulls every number explicitly tied to "pull"/"haul" out
# of the comment and returns the largest; NA when no such count is recorded.
extract_n_hauls <- function(comment) {
  if (is.na(comment)) return(NA_real_)
  s <- tolower(comment)

  num_words <- c(one = "1", two = "2", three = "3", four = "4", five = "5", six = "6")
  for (w in names(num_words)) {
    s <- str_replace_all(s, paste0("\\b", w, "\\b"), num_words[[w]])
  }

  ord_words <- c("1st" = 1, first = 1, "2nd" = 2, second = 2,
                 "3rd" = 3, third = 3, "4th" = 4, fourth = 4,
                 "5th" = 5, fifth = 5, "6th" = 6, sixth = 6)
  ord_alt <- paste(names(ord_words), collapse = "|")

  candidates <- numeric(0)

  m <- str_match_all(s, "\\d+\\s+of\\s+(\\d+)\\s*(?:pulls?|hauls?)")[[1]]
  if (nrow(m) > 0) candidates <- c(candidates, as.numeric(m[, 2]))

  m <- str_match_all(s, "(\\d+)\\s*(?:seine\\s+)?pulls?\\b")[[1]]
  if (nrow(m) > 0) candidates <- c(candidates, as.numeric(m[, 2]))
  m <- str_match_all(s, "(\\d+)\\s*hauls?\\b")[[1]]
  if (nrow(m) > 0) candidates <- c(candidates, as.numeric(m[, 2]))

  m <- str_match_all(s, paste0("(", ord_alt, ")\\s*(?:pull|haul)"))[[1]]
  if (nrow(m) > 0) candidates <- c(candidates, unname(ord_words[m[, 2]]))
  m <- str_match_all(s, paste0("(?:pull|haul)\\s*#?\\s*(\\d+|", ord_alt, ")"))[[1]]
  if (nrow(m) > 0) {
    vals <- ifelse(str_detect(m[, 2], "^\\d+$"), as.numeric(m[, 2]), unname(ord_words[m[, 2]]))
    candidates <- c(candidates, vals)
  }

  if (length(candidates) == 0) return(NA_real_)
  max(candidates, na.rm = TRUE)
}

substrate_lookup <- tibble::tibble(
  code = c("Fine", "Small", "Medium", "Pavement", "Boulder"),
  definition = c(
    "Fine - small gravel (0-50mm) (0-2in.)",
    "Small - medium gravel (50-150mm) (2-6in.)",
    "Medium - large cobble (150-300mm) (6-12in.)",
    "Pavement (Boat Ramp)",
    "Boulder (>300mm) (>12in.)"
  )
)

# Helper: map a full substrate string to its short code
map_substrate_code <- function(x) {
  case_when(
    str_detect(x, "^Fine")     ~ "Fine",
    str_detect(x, "^Small")    ~ "Small",
    str_detect(x, "^Medium")   ~ "Medium",
    str_detect(x, "^Pavement") ~ "Pavement",
    str_detect(x, "^Boulder")  ~ "Boulder",
    TRUE ~ NA_character_
  )
}

# Species cleaning: fixes typos, standardizes formatting, and expands
# known abbreviation codes. Entries marked "# VERIFY" are my best guess
# based on context — please confirm against your field datasheet codes
# before trusting them in analysis.
clean_species <- function(x) {
  x_trim <- str_trim(x)

  case_when(
    is.na(x_trim) ~ NA_character_,
    x_trim %in% c("NO FISH CAUGHT") ~ NA_character_,

    x_trim == "Chjnook Salmon- Spring" ~ "Chinook Salmon - Spring",
    x_trim == "Chinook Salmon- Fall" ~ "Chinook Salmon - Fall",
    x_trim == "Chinook Salmon- Late Fall" ~ "Chinook Salmon - Late Fall",
    x_trim == "Chinook Salmon- Winter" ~ "Chinook Salmon - Winter",
    x_trim == "Chinook Salmon- Unknown Race Tagged" ~ "Chinook Salmon - Unknown Race Tagged",
    x_trim == "Chinook Salmon - Spring Tagged" ~ "Chinook Salmon - Spring Tagged",
    x_trim == "Chinook Salmon - Fall Tagged" ~ "Chinook Salmon - Fall Tagged",
    x_trim == "Chinook Salmon" ~ "Chinook Salmon - Unknown Race",
    x_trim == "Unidentified salmonid" ~ "Unidentified Salmonid",
    x_trim == "UNID Sunfish" ~ "Unidentified Sunfish",

    x_trim == "Sacramento Squawfish or Hardhead" ~ "Sacramento Pikeminnow or Hardhead",
    x_trim == "sasq" ~ "Sacramento Pikeminnow",
    x_trim == "Sacramento Squawfish" ~ "Sacramento Pikeminnow",
    x_trim == "Pikeminnow/Hardhead" ~ "Sacramento Pikeminnow or Hardhead",

    x_trim == "SD" ~ "Speckled Dace",
    x_trim == "GS" ~ "Green Sunfish",
    x_trim %in% c("min") ~ "Unidentified Juvenile Minnow",
    x_trim %in% c("wag") ~ "Wakasagi",
    x_trim %in% c("chnw") ~ "Chinook Salmon - Winter",
    x_trim %in% c("chnlf", "CHNLF") ~ "Chinook Salmon - Late Fall",
    x_trim %in% c("chnf") ~ "Chinook Salmon - Fall",

    # VERIFY - pending confirmation from data owner
    x_trim %in% c("MSQ", "msq") ~ "Western Mosquitofish", # confirmed by Kassie
    x_trim %in% c("CHNSC") ~ "Chinook Salmon - Spring (ad-clipped)", # confirmed by Kassie, need to add the ad clipped to the correct column
    x_trim %in% c("CHNs") ~ "Chinook Salmon - Spring",# confirmed by Kassie
    x_trim %in% c("SPB", "spb") ~ "Spotted Bass",# confirmed by Kassie
    x_trim %in% c("Scp") ~ "Unid Juvenile Sculpin",# confirmed by Kassie, check 'juvenile' is okay?
    x_trim %in% c("Res") ~ "Rainbow Trout (wild)",
    x_trim %in% c("Pink") ~ "Pink Salmon",
    x_trim %in% c("b") ~ NA_character_,

    TRUE ~ x_trim
  ) |>
    str_replace("^Unid\\b", "Unidentified") # will remove "b" from dataset
}


#  process 1997-2001 -------------------------------------------------------------------
seine_1997 <- raw_1997 |>
  clean_names() |>
  select(-c(weight, mark, dead, crew, recorder)) |>
  rename(
    id               = individ_auto_id,
    lifestage_code   = salmon_life_stage_code,
    run              = race,
    gear_size_code   = gear_size_code,
    survey_condition = condition_code,
    weather_code     = weather_code,
    depth_dist_1     = depth1dist,
    depth_dist_2     = depth2dist,
    depth_1          = depth1, # TODO: include in documentation: full distance out
    depth_2          = depth2, # TODO: include in documentation: closest to shore
    # averaging these wouldn't be a good representation of the actual depth.
    substrate_1      = hu_csubstrate,
    cover_1          = hu_ccover,
    stream_feature   = hu_cunit,
    species_code     = species_code,
    secchi           = sechi
  ) |>
  mutate(
    source           = "1997-2001",
    # This era records water_temp in Fahrenheit and uses 0 as a "not recorded"
    # placeholder (it also uses NA - the coding is inconsistent). Converting a
    # raw 0 would manufacture a reading of -17.8 C, which is what the 161 rows
    # on 1999-06-11 were showing. na_if() must run BEFORE the conversion so the
    # sentinel never becomes a number. Real values here span 44-80 F
    # (6.7-26.7 C), so 0 is a sentinel rather than the low end of a continuum.
    water_temp       = weathermetrics::fahrenheit.to.celsius(na_if(water_temp, 0), round = 1),
    species          = coalesce(organism_map[species_code], species_code),
    lifestage        = decode_lifestage(as.character(lifestage_code)),
    survey_condition = condition_map[as.character(survey_condition)],
    weather          = weather_map[weather_code],
    stream_feature   = unit_map[stream_feature],
    gear_size        = case_when(
      gear_size_code == 1 ~ "25 foot beach seine with bag",
      gear_size_code == 2 ~ "39 foot beach seine with bag",
      gear_size_code == 3 ~ "50 foot beach seine with bag",
      gear_size_code == 4 ~ "100 foot beach seine with bag",
      gear_size_code == 5 ~ "backpack shock into any seine"
    ),
    substrate_1      = substrate_map[as.character(substrate_1)],
    cover_1          = cover_map[as.character(cover_1)],
    date             = as.Date(date),
    latitude         = NA_real_,
    longitude        = NA_real_,
    channel          = NA_character_,
    sample_id        = NA_real_,
    gear_type        = gear_type,
    sample_shape     = case_when(
      sample_shape == 0 ~ "net",
      sample_shape == 1 ~ "box seine technique",
      sample_shape == 2 ~ "sweep seine technique"
    )
  ) |>
  select(source, date, sample_id, seine_id, id, location, latitude, longitude, channel,
         gear_type, gear_size, survey_condition, water_temp, weather, secchi, flow,
         species, fork_length, lifestage, run,
         length, width, distance_out, depth_1, depth_2, depth_dist_1, depth_dist_2,
         substrate_1, cover_1, stream_feature, sample_shape, sample_area, comments)

glimpse(seine_1997)

# process 2008-2014 -------------------------------------------------------
# See for original pre-processing:
# https://github.com/FlowWest/edi-feather-beach-seine/blob/add-seine-db/data-raw/jpe-datasets/feather_seine_2008-2014.md
#
# Convert UTM coordinates to decimal degrees
points_utm <- cbind(raw_2008$x_coord, raw_2008$y_coord)
v   <- terra::vect(points_utm, crs = "+proj=utm +zone=10 +datum=WGS84 +units=m")
ll  <- terra::project(v, "+proj=longlat +datum=WGS84")
lonlat <- terra::geom(ll)[, c("x", "y")]

seine_2008 <- raw_2008 |>
  clean_names() |>
  mutate(longitude = lonlat[, "x"],
         latitude  = lonlat[, "y"]) |>
  select(-c(x_coord, y_coord, dead, weight_g, total_length, objectid, l_id,
            efbs_length, efbs_width, efbs_depth_top, efbs_depth_bottom,
            efbs_velocity_top, efbs_velocity_bottom, bs_velocity_1_2,
            bs_velocity_full, gear_height, dissolved_oxygen, ec)) |>
  rename(
    lifestage_code   = salmonid_life_stage,
    survey_condition = condition_code,
    weather_code     = weather_code,
    water_temp       = temperature,
    length           = bs_start_length,
    width            = bs_close_width,
    distance_out     = bs_distance_out,
    depth_avg          = bs_depth_1_2, #TODO need to understand this value
   # depth_2          = bs_depth_full,#TODO need to understandt this value;
    # MW: I am going to remove the full depth following the guidance from Kassie, Ryon for
    # 2015-2025 data. bs_depth_1_2 should be the average depth.
    stream_feature   = rpg_ru,
    location         = site_name
  ) |>
  mutate(
    source           = "2008-2014",
    date             = as.Date(date),
    species          = coalesce(organism_map[toupper(species)], toupper(species)),
    lifestage        = decode_lifestage(as.character(lifestage_code)),
    survey_condition = condition_map[as.character(survey_condition)],
    weather          = weather_map[weather_code],
    stream_feature   = unit_map[stream_feature],
    gear_size        = gear_map$gear_size[match(gear_code, gear_map$gear_num)],
    substrate_1      = substrate_map[as.character(substrate_1)],
    substrate_2      = substrate_map[as.character(substrate_2)],
    substrate_3      = substrate_map[as.character(substrate_3)],
    cover_1          = cover_map[as.character(cover_1)],
    cover_2          = cover_map[as.character(cover_2)],
    cover_3          = cover_map[as.character(cover_3)],
    channel          = NA_character_,
    run              = NA_character_,
    seine_id         = NA_real_,
    secchi           = NA_real_,
    sample_shape     = NA_character_,
    sample_area      = NA_real_,
    comments         = NA_character_
  ) |>
  select(source, date, sample_id, seine_id, id, location, latitude, longitude, channel,
         gear_type, gear_size, survey_condition, water_temp, weather, secchi, flow,
         species, fork_length, lifestage, run, count,
         length, width, distance_out, depth_avg,
         substrate_1, substrate_2, substrate_3, cover_1, cover_2, cover_3,
         stream_feature, sample_shape, sample_area, comments)

glimpse(seine_2008)


# process 2015-2025 (accdb) -----------------------------------------------

loc_clean <- location_lu |>
  clean_names() |>
  select(objectid, site_name, channel,
         longitude = utm_easting, latitude = utm_northing)

catch_clean <- catch_tbl |>
  clean_names() |>
  left_join(
    organism_code_lu |> clean_names() |> select(organism_code, common_name),
    by = c("species" = "organism_code")
  ) |>
  mutate(label = coalesce(common_name, species))

# TODO: figure out fix three dates that are not parsing correctly
# (sample_id 1198, 1502, 1645 are stored as "01/00/00" in the raw accdb -
# day 00 / year 00 - so they parse to NA. Kassie is cross-checking these
# sample ids; they may be catch records whose sample record was deleted.)
sample_clean <- sample_tbl |>
  clean_names() |>
  mutate(
    date = mdy_hms(date),
    year = year(date)
  )

seine_accdb <- catch_clean |>
  left_join(sample_clean |> select(-channel), by = "sample_id") |>
  left_join(loc_clean, by = c("site_id" = "objectid")) |>
  left_join(gear_map, by = c("gear_code" = "gear_num")) |>
  mutate(
    source           = "2015-2025",
    date             = as.Date(date),
    species          = coalesce(organism_map[species], species),
    lifestage        = decode_lifestage(as.character(salmonid_life_stage)),
    survey_condition = condition_map[as.character(condition_code)],
    weather          = weather_map[weather_code],
    stream_feature   = unit_map[rpg_ru],
    substrate_1      = substrate_map[as.character(substrate_1)],
    substrate_2      = substrate_map[as.character(substrate_2)],
    substrate_3      = substrate_map[as.character(substrate_3)],
    cover_1          = cover_map[as.character(cover_1)],
    cover_2          = cover_map[as.character(cover_2)],
    cover_3          = cover_map[as.character(cover_3)],
    run              = NA_character_,
    seine_id         = NA_real_,
    secchi           = NA_real_,
    sample_shape     = NA_character_,
    sample_area      = NA_real_,
    location         = site_name,
    id               = NA_real_,
    weight           = weight_g,
    comments         = case_when(
      !is.na(comments.y) & !is.na(comments.x) ~ paste(comments.y, comments.x, sep = "; "),
      !is.na(comments.y)                      ~ comments.y,
      !is.na(comments.x)                      ~ comments.x,
      TRUE                                     ~ NA_character_
    )
  ) |>
  rename(
    water_temp   = temperature,
    length       = bs_start_length,
    width        = bs_close_width,
    distance_out = bs_distance_out,
    depth_avg      = bs_depth_1_2 # this is the average
    #depth_2      = bs_depth_full # remove
  ) |>
  select(source, date, sample_id, seine_id, id, location, latitude, longitude, channel,
         gear_type, gear_size, survey_condition, water_temp, weather, secchi, flow,
         species, fork_length, lifestage, run, weight, count,
         length, width, distance_out, depth_avg,
         substrate_1, substrate_2, substrate_3, cover_1, cover_2, cover_3,
         stream_feature, sample_shape, sample_area, comments)

glimpse(seine_accdb)


# combine data  -----------------------------------------------------------

all_seine_combined <- bind_rows(seine_1997, seine_2008, seine_accdb) |>
  mutate(year = year(date))

# dataset specific modifications -----------------------------------------------
issue_log <- tibble::tibble()

non_seine_gear_types <- all_seine_combined |>
  filter(gear_type %in% c("NETS", "EF_SE", "EF-SE")) |>
  write_csv(here::here("edi-seine", "data", "clean", "diagnostics", "non_seine_gear_types.csv"))

issue_log <- dplyr::bind_rows(
  issue_log,
  hrlpub::log_issue(
    issue = "non-seine gear types",
    rows_affected = nrow(non_seine_gear_types),
    action = "removed gear types of NETS, EF_SE, and EF-SE",
    n_total = nrow(all_seine_combined),
    details_path = "data/clean/diagnostics/non_seine_gear_types.csv"
  )
)

seine_sample_shape <- all_seine_combined |>
  select(date, sample_shape) |>
  na.omit() |>
  write_csv(here::here("edi-seine", "data", "clean", "diagnostics", "seine_sample_shape.csv"))

issue_log <- dplyr::bind_rows(
  issue_log,
  hrlpub::log_issue(
    issue = "sample shape not needed in final dataset",
    rows_affected = nrow(seine_sample_shape),
    action = "removed sample_shape column which includes: sweep seine technique, box seine technique, and net",
    n_total = nrow(all_seine_combined),
    details_path = "data/clean/diagnostics/seine_sample_shape.csv"
  )
)

# link seine locations to river mile via the Subsite Table crosswalk --------

# `Subsite Table.xlsx` (data-raw/background) maps the granular seine
# `location` values (SubSite Details) to the coarser named reaches in
# `river_miles` (Site.xlsx). Matched in three tiers, most to least direct:
#   1. location is already one of the canonical river_miles site names
#   2. exact string match to Subsite Table's SubSite Details column
#   3. match after normalizing case/whitespace/punctuation only (an
#      assumption, since it relies on the two strings being formatting
#      variants of the same site, not literally identical)
# Locations not covered by Subsite Table (boat ramps, relative-distance
# descriptions, a few spelling variants like "MacFarland" vs "McFarland")
# are left unmatched rather than guessed.
normalize_site_name <- function(x) {
  x |>
    str_squish() |>
    tolower() |>
    str_replace_all("’", "'") |>
    str_replace_all("\\s*-\\s*", "-") |>
    str_replace_all("\\.", "")
}

subsite_lookup_norm <- subsite_lookup |>
  mutate(location_norm = normalize_site_name(sub_site_details))

# location counts + which source table(s) (1997-2001 / 2008-2014 / 2015-2025)
# each location shows up in, so the saved crosswalk covers every era
distinct_locations <- all_seine_combined |>
  group_by(location) |>
  summarise(
    n_rows  = n(),
    sources = paste(sort(unique(source)), collapse = ", "),
    .groups = "drop"
  ) |>
  mutate(location_norm = normalize_site_name(location))

river_mile_tier0 <- distinct_locations |>
  filter(location %in% river_miles$site_name) |>
  left_join(river_miles, by = c("location" = "site_name")) |>
  mutate(river_mile_site = location, match_method = "exact_river_miles_site_name") |>
  select(location, n_rows, sources, river_mile_site, river_mile,
         river_mile_site_id = site_id, match_method)

river_mile_tier1 <- distinct_locations |>
  filter(!location %in% river_mile_tier0$location) |>
  inner_join(
    subsite_lookup |> select(sub_site_details, river_mile_site = site_name, river_mile_site_id = site_id),
    by = c("location" = "sub_site_details")
  ) |>
  left_join(river_miles |> select(site_name, river_mile), by = c("river_mile_site" = "site_name")) |>
  mutate(match_method = "exact_subsite_table") |>
  select(location, n_rows, sources, river_mile_site, river_mile, river_mile_site_id, match_method)

river_mile_tier2 <- distinct_locations |>
  filter(!location %in% c(river_mile_tier0$location, river_mile_tier1$location)) |>
  inner_join(
    subsite_lookup_norm |> select(location_norm, matched_subsite_text = sub_site_details,
                                   river_mile_site = site_name, river_mile_site_id = site_id),
    by = "location_norm"
  ) |>
  left_join(river_miles |> select(site_name, river_mile), by = c("river_mile_site" = "site_name")) |>
  mutate(match_method = "normalized_subsite_table") |>
  select(location, n_rows, sources, matched_subsite_text, river_mile_site, river_mile,
         river_mile_site_id, match_method)

# GUESS TABLE -----------------------------------------------------------
# `location` only matched Subsite Table's `matched_subsite_text` after
# stripping case/whitespace/punctuation, not verbatim, so `river_mile_site`
# started as an assumption rather than a confirmed lookup.
# VERIFIED 2026-08-19 (Maddee Rubenson) - all three confirmed correct:
#   "HATCHERY DITCH"            -> Hatchery Ditch/Riffle (matched "Hatchery Ditch")
#   "MOE'S DITCH"               -> Moe's                 (matched "Moe's Ditch")
#   "Auditorium RL -Downstream" -> Auditorium Riffle      (matched "Auditorium RL - Downstream")
river_mile_guesses <- river_mile_tier2 |>
  select(location, matched_subsite_text, river_mile_site)

print(river_mile_guesses, n = Inf)

river_mile_unresolved <- distinct_locations |>
  filter(!location %in% c(river_mile_tier0$location, river_mile_tier1$location, river_mile_tier2$location)) |>
  mutate(
    river_mile_site    = NA_character_,
    river_mile         = NA_real_,
    river_mile_site_id = NA_real_,
    match_method       = "unresolved_not_in_subsite_table"
  ) |>
  select(location, n_rows, sources, river_mile_site, river_mile, river_mile_site_id, match_method) |>
  write_csv(here::here("edi-seine", "data", "clean", "diagnostics", "river_mile_unresolved.csv"))

# MANUAL CROSSWALK - hand-edit this table -----------------------------------
# Every location Subsite Table couldn't resolve (river_mile_unresolved above)
# gets a row here. Fill in `river_mile_site` with one of the 41 names in
# river_miles$site_name once you've confirmed it, and note your reasoning in
# `comment` - the same way clean_species() documents its manual calls.
# Leave river_mile_site NA for anything you can't confidently place; it will
# stay unresolved. Re-run the script after editing to pick up your changes.
river_mile_manual_crosswalk <- tibble::tribble(
  ~location,                                            ~river_mile_site, ~comment,
  "Yuba City Boat Ramp",                                'Yuba City',    NA_character_,
  "Live Oak Boat Ramp",                                 'Live Oak',    NA_character_,
  "Boyd Pump Boat Ramp",                                'Boyds',    NA_character_,
  "Thermalito Boat Ramp",                               'Thermalito Outlet',    NA_character_,
  "G95 (Bar Complex btwn Big Hole Isl/Hour Riffle)",    'G95',    NA_character_,
  "Montgomery Street (River Bend Park)",                'Riverbend',    NA_character_,
  "Bedrock Park",                                       "Bedrock Riffle",    NA_character_,
  "Gridley Boat Ramp",                                  'Gridley',    NA_character_,
  "1/4 Mile Downstream of Yuba City Boat Ramp",         'Yuba City',    NA_character_,
  "1/4 Mile Upstream of Live Oak Boat Ramp",            'Live Oak',    NA_character_,
  "Boyds Bump Boat Launch- Across",                     'Boyds',    NA_character_,
  "Big Riffle",                                         'Big Bar/Riffle',    NA_character_,
  "Hour Bar Side Channel (alternate)",                  'Hour',    NA_character_,
  "Vance Avenue Boat Ramp",                             'Vance',    NA_character_,
  "Developing Riffle",                                  'McFarland',    NA_character_,
  "Hour Main RL - Downstream",                          'Hour',    NA_character_,
  "Eye side channel - Bottom",                          'Eye Riffle',    NA_character_,
  "Steep side channel - Upstream",                      'Steep Riffle',    NA_character_,
  "Hatchery Riffle",                                    'Hatchery Ditch/Riffle',    NA_character_,
  "McFarland Backwater RR",                             'McFarland',    NA_character_,
  "Steep Main RR - Downstream",                         'Steep Riffle',    NA_character_,
  "Steep Backwater",                                    'Steep Riffle',    NA_character_,
  "Hour Glide",                                         'Hour',    NA_character_,
  "Steep Main RR - Upstream",                           'Steep Riffle',    NA_character_,
  "1/4 Mile Upstream of Boyd Pump Boat Ramp",           'Boyds',    NA_character_,
  "McFarland Main RR - Upstream",                       'McFarland',    NA_character_,
  "Big Hole Island Boat Ramp",                          'Vance',    NA_character_,
  "Below Gridley Boat Ramp",                            'Gridley',    NA_character_,
  "MacFarland",                                         'McFarland',    NA_character_,
  "Below Big Hole",                                     'Vance',    NA_character_,
  "Junkyard side channel 1 - RR",                       'Junkyard',    NA_character_,
  "Mulberry Beach RR - Downstream",                     NA_character_,    NA_character_, # TODO
  "G-95",                                               'G95',    NA_character_,
  "HATCHERY DITCH - bottom",                            'Hatchery Ditch/Riffle',    NA_character_,
  "Between Steep and Eye (Wier Site)",                  'Steep Riffle',    NA_character_,
  "Lower MacFarland",                                   'McFarland',    NA_character_,
  "Trailer Park Riffle",                                'Trailer Park',    NA_character_,
  "Lower McFarlan Main RL",                             'McFarland',    NA_character_,
  "Junkyard Main RR",                                   'Junkyard',    NA_character_,
  "Junkyard side channel 1 - RL",                       'Junkyard',    NA_character_,
  "Hatchery Ditch (Bottom)",                            'Hatchery Ditch/Riffle',    NA_character_,
  "Boyds Pump-  1 mile Downstream RL",                  'Boyds',    NA_character_,
  "Steep side channel - Downstream",                    'Steep Riffle',    NA_character_,
  "Vance West RL - Upstream",                           'Vance',    NA_character_,
  "Mathews Riffle",                                     'Matthews',    NA_character_,
  "Below Big Hole Island",                              'Vance',    NA_character_,
  "Junkyard SC RR",                                     'Junkyard',    NA_character_,
  "Auditorium RR - Downstream",                         'Auditorium Riffle',    NA_character_,
  "Lower Hatchery ditch",                               'Hatchery Ditch/Riffle',    NA_character_,
  "Lower Trailer Park Backwater RL",                    'Trailer Park',    NA_character_,
  "250 yards below Honcut Confluence",                  NA_character_,    NA_character_, # TODO
  "Gridley Pool",                                       "Gridley",    NA_character_,
  "Hour Backwater",                                     "Hour",    NA_character_,
  "1/4 Mile Upstream of Big Hole Island",               "Vance",    NA_character_,
  "Below Junkyard Riffle",                              "Junkyard",    NA_character_,
  "Below Long Glide",                                   NA_character_,    NA_character_,# TODO
  "Below Upper Herringer",                              'Herringer',    NA_character_,
  "Herringer Side Channel",                             'Herringer',    NA_character_,
  "Below Herringer Riffle",                             'Herringer',    NA_character_,
  "Eye Main RR - Upstream",                             'Eye Riffle',    NA_character_,
  "Gridley Riffle",                                     'Gridley',    NA_character_,
  "Eye Riffle - Upper Side Channel",                    'Eye Riffle',    NA_character_,
  "gridley Boat launch side channel",                   'Gridley',    NA_character_,
  "Downstream Clay Banks RR",                           NA_character_,    NA_character_,# TODO
  "Pollywog Beach",                                     NA_character_,    NA_character_,# TODO
  "Clay Banks upstream backwater RL",                   NA_character_,    NA_character_,# TODO
  "Shallow Riffle",                                     'Cox Riffle',    NA_character_,
  "Ellis Road Beach",                                   NA_character_,    NA_character_,# TODO
  "Gateway Riffle",                                     'Gateway',    NA_character_,
  "Robinson's Riffle",                                  'Robinson',    NA_character_,
  "u/s end of bar complex, d/s of big hole islands",    'Vance',    NA_character_,
  "Shallow Riffle  (523)",                              'Cox Riffle',    NA_character_,
  "Downstream Bum Beach",                               NA_character_,    NA_character_,# TODO
  "Above G95 SC - RR",                                  'G95',    NA_character_,
  "d/s end of big hole islands",                        'Vance',    NA_character_,
  "bend backwater (562)",                               NA_character_,    NA_character_,# TODO
  "GOOSE Riffle",                                       'Goose Riffle',    NA_character_,
  "Unit 26A",                                           NA_character_,    NA_character_,# TODO
  "Vance Avenue",                                       'Vance',    NA_character_,
  "Vance East Main RL",                                 'Vance',    NA_character_,
  "Upper Heringer",                                     'Herringer',    NA_character_,
  "Hatchery Ditch(upper)",                              'Hatchery Ditch/Riffle',    NA_character_,
  "24th St. Levee OWA",                                 NA_character_,    NA_character_,# TODO
  "G95 Downstream RL",                                  'G95',    NA_character_,
  "Junkyard Above RR",                                  'Junkyard',    NA_character_,
  "Junkyard Riffle",                                    'Junkyard',    NA_character_,
  "Robinson's Riffle Side Channel",                     'Robinson',    NA_character_,
  "Steep Riffle Side Channel",                          'Steep Riffle',    NA_character_,
  "Palm avenue access",                                 'Palm Ave',    NA_character_,
  "Big Bar",                                            'Big Bar/Riffle',    NA_character_,
  "between bend backwater and honcutt confluence(566)", 'Honcut Creek',    NA_character_,
  "Eye Main RL",                                        'Eye Riffle',    NA_character_,
  "Old Thermalito",                                     'Thermalito Outlet',    NA_character_,
  "Gridley Ramp",                                       'Gridley',    NA_character_,
  "Honcut Confluence",                                  'Honcut Creek',    NA_character_,
  "upper herringer (532)",                              'Herringer',    NA_character_
)

# fold in any manual calls made above; anything still NA stays unresolved
river_mile_unresolved <- river_mile_unresolved |>
  select(-river_mile_site, -river_mile, -river_mile_site_id, -match_method) |>
  left_join(river_mile_manual_crosswalk, by = "location") |>
  left_join(river_miles |> select(site_name, river_mile), by = c("river_mile_site" = "site_name")) |>
  left_join(river_miles |> select(river_mile_site = site_name, river_mile_site_id = site_id), by = "river_mile_site") |>
  mutate(match_method = if_else(is.na(river_mile_site), "unresolved_not_in_subsite_table", "manual_crosswalk")) |>
  select(location, n_rows, sources, river_mile_site, river_mile, river_mile_site_id, match_method)

# comprehensive location -> river mile crosswalk covering every distinct
# `location` across all three source tables (1997-2001, 2008-2014, 2015-2025)
# that feed all_seine_combined
location_river_mile_crosswalk <- bind_rows(
  river_mile_tier0,
  river_mile_tier1,
  river_mile_tier2 |> select(-matched_subsite_text),
  river_mile_unresolved
) |>
  arrange(desc(n_rows)) |>
  write_csv(here::here("edi-seine", "data", "clean", "diagnostics", "location_river_mile_crosswalk.csv"))

location_river_mile_lookup <- location_river_mile_crosswalk |>
  filter(match_method != "unresolved_not_in_subsite_table") |>
  select(location, river_mile_site, river_mile, river_mile_site_id)

issue_log <- dplyr::bind_rows(
  issue_log,
  hrlpub::log_issue(
    issue = "seine location not found in Subsite Table river mile crosswalk",
    rows_affected = sum(location_river_mile_crosswalk$n_rows[location_river_mile_crosswalk$match_method == "unresolved_not_in_subsite_table"]),
    action = "left river_mile_site/river_mile as NA rather than guess a match",
    n_total = nrow(all_seine_combined),
    details_path = "data/clean/diagnostics/location_river_mile_crosswalk.csv"
  )
)


# CREATE CLEAN DATA -------------------------------------------------------------------------
# Data modifications/cleaning:
# 1. removed gear types of NETS, EF_SE, and EF-SE
# 2. created one sample id based on sample id and seine id since they were redundant and dependent on the input dataset
# 3. if gear type was NA, we made it SEIN
# 4. extracted the number of hauls from the comments section
# 5. removed flow (gage), weather, id
# 6. Do not represent substrate and cover as “dominant” and “secondary”
#     etc because they record all that is present and then enter or order of
#     entry determines the “dominant” and “secondary”
# 7. removed sample shape

# TODO: substrate description for metadata:
# Fine - small gravel (0-50mm) (0-2in.)
# Small - medium gravel (50-150mm) (2-6in.)
# Medium - large cobble (150-300mm) (6-12in.)
# Pavement (Boat Ramp)
# Boulder (>300mm) (>12in.)
#

# locations that don't match river mile locations - see
# location_river_mile_crosswalk.csv (written above) for the full list with row counts
location_river_mile_crosswalk |>
  filter(match_method == "unresolved_not_in_subsite_table") |>
  pull(location)

# look at raw species, pre-cleaning
all_seine_combined |>
  pull(species) |>
  unique()

# all NA... should just be removed
all_seine_combined |>
  filter(species == "b") |>
  glimpse()

# CREATE CLEAN DATA OBJECT

all_seine_clean <- all_seine_combined |>
  # Raw accdb date-entry errors, each keyed on sample_id so they can only ever
  # touch the intended row. No cross-era collision risk: accdb sample_ids run
  # 352-1736, the 2008-2014 range is 50-351, and 1997-2001 has sample_id = NA.
  #
  # sample_id 1704 is entered as 06/16/05, which parses to 2005 - outside this
  # dataset's 2015-2025 range. Typo for 06/16/25: sample_ids 1701-1705 are all
  # 06/16/25, this record's time (12:25) falls between its neighbors 1703
  # (11:58) and 1705 (13:30), and all three share the same flow (4400) and
  # weather (CLR), i.e. the same survey day.
  #
  # sample_id 1502 and 1645 are entered as "01/00/00" (day 00 / year 00) and so
  # parse to NA. Each is bracketed by same-day records sharing flow and weather,
  # which recovers the survey date:
  #   1502 -> 2023-07-18 (time 11:20 sits between 1501 @ 10:30 and 1503 @ 12:08;
  #                       all three flow 5000, weather CLR)
  #   1645 -> 2024-07-18 (time 12:20 follows 1644 @ 11:27; both flow 9000, CLR)
  # There is a third "01/00/00" record in SAMPLE TBL (sample_id 1198), but it
  # has 0 rows in Catch TBL. This pipeline is catch-driven (catch_clean is the
  # left side of the join), so that sample never reaches this dataset and needs
  # no fix here - the NA dates that remain after this are all rows with no
  # sample_id at all.
  # NOTE: per the note in qc/qc-data.R, Kassie is cross-checking the NA-date
  # sample ids - so 1502 and 1645 should be confirmed against that review
  # rather than treated as settled by the neighbor inference alone.
  mutate(date = case_when(
    sample_id == 1704 & year(date) == 2005 ~ update(date, year = 2025),
    sample_id == 1502 & is.na(date)        ~ as.Date("2023-07-18"),
    sample_id == 1645 & is.na(date)        ~ as.Date("2024-07-18"),
    TRUE                                   ~ date
  )) |>
  # `year` was derived back in all_seine_combined, i.e. BEFORE the corrections
  # above, so it has to be recomputed here or it stays stale: sample_id 1704
  # would keep year 2005 against a 2025 date, and 1502/1645 would keep year NA
  # against a valid date.
  mutate(year = year(date)) |>
  # A fork_length of 0 isn't a measurement - it's a plus count, i.e. a subset
  # of the catch was measured and the remainder was only counted. Set those to
  # NA so they aren't treated as real 0mm lengths in summaries/analysis; the
  # `count` field still carries the number of fish. Happens twice, both
  # fork_length == 0 (no negative values in the data): 2008-08-26 (sample_id
  # 123, sacramento sucker, count 38) and 2023-02-21 (sample_id 1415, chinook
  # salmon, count 89).
  mutate(fork_length = if_else(fork_length <= 0, NA_real_, fork_length)) |>
  # sample_id 1628 (2024-07-15, Bedrock Park RL) records water_temp 147, it
  # might be 14.7 otherwise mark as NA. TODO - checking with Kassie, Ryon
  mutate(water_temp = case_when(
    sample_id == 1628 & water_temp == 147 ~ NA_real_,
    TRUE                                  ~ water_temp
  )) |>
  # species b is all NA for every other column except count of 1
  filter(species != "b") |>
  left_join(location_river_mile_lookup, by = "location") |>
  filter(!gear_type %in% c("NETS", "EF_SE", "EF-SE")) |>
  mutate(
    sample_id = coalesce(sample_id, seine_id),
    gear_type = coalesce(gear_type, "SEIN"),
    n_hauls   = map_dbl(comments, extract_n_hauls)
  ) |>
  # Methods define "seine area" as length, width, and average depth of the
  # haul, i.e. sample_area = length * width * depth. 1997-2001 already
  # supplies sample_area directly from the raw data; 2008+ data doesn't
  # include a pre-computed area, so derive it here from length/width/depth.
  # TODO: double check this
  mutate(sample_area = coalesce(sample_area, length * width * depth_avg)) |>
  # COLLAPSE SUBSTRATE VAR
  mutate(
    substrate_1_code = map_substrate_code(substrate_1),
    substrate_2_code = map_substrate_code(substrate_2),
    substrate_3_code = map_substrate_code(substrate_3)
  ) |>
  rowwise() |>
  mutate(
    substrate = paste(
      na.omit(c(substrate_1_code, substrate_2_code, substrate_3_code)),
      collapse = ", "
    )
  ) |>
  ungroup() |>
  rowwise() |>
  # COLLAPSE COVER VAR
  mutate(
    cover = paste(
      na.omit(c(cover_1, cover_2, cover_3)),
      collapse = ", "
    )
  ) |>
  # CLEAN SPECIES:
  mutate(species_clean = clean_species(species)) |>
  mutate(
    adipose_clipped = case_when(
      str_detect(species_clean, "Tagged") ~ TRUE,
      str_detect(species_clean, "\\(ad clipped\\)") ~ TRUE,
      str_detect(species_clean, "^Chinook Salmon|^Steelhead Trout") ~ FALSE, # NOTE: the above statement overrides this. If steelhead
      # trout is adipose clipped, it will show up in final dataset as o. mykiss clipped
      TRUE ~ NA
    ),
    run = case_when(
      str_detect(species_clean, "Late Fall") ~ "Late Fall",
      str_detect(species_clean, "Fall") ~ "Fall",
      str_detect(species_clean, "Spring") ~ "Spring",
      str_detect(species_clean, "Winter") ~ "Winter",
      str_detect(species_clean, "Unknown Race") ~ "Unknown",
      TRUE ~ NA_character_
    ),
    id_note = case_when(
      str_detect(species_clean, "form not i.d.'d") ~ "form not identified",
      TRUE ~ NA_character_
    )
  ) |>
  mutate(
    species_final = tolower(case_when(
      str_detect(species_clean, "^Chinook Salmon") ~ "Chinook Salmon",
      str_detect(species_clean, "^Rainbow Trout|^Steelhead Trout") ~ "O. Mykiss", # FLAG - there are clipped steelhead.
      species_clean == "Smallmouth Bass" ~ "Small Mouth Bass",
      species_clean == "Largemouth Bass" ~ "Large Mouth Bass",
      species_clean == "Sacramento Pikeminnow or Hardhead" ~ "Sacramento Pikeminnow or hardhead",
      TRUE ~ species_clean
    ))
  ) |>
  mutate(species = species_final) |>
  select(-seine_id, -flow, -weather, -comments, -sample_shape,
         -substrate_1, -substrate_2, -substrate_3,
         -substrate_1_code, -substrate_2_code, -substrate_3_code,
         -cover_1, -cover_2, -cover_3, -id, -source,
         -species_clean, -species_final,
         -depth_dist_1, -depth_dist_2,
         -river_mile_site, -river_mile_site_id, -id_note,
         -latitude, -longitude) |>
  # there are 37 rows with NA date and sample_id. These are being removed.
  filter(!is.na(date))

write_csv(all_seine_clean, here::here("edi-seine", "data", "clean", "all_seine_clean.csv"))


