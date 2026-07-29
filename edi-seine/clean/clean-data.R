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
    x_trim %in% c("MSQ", "msq") ~ "Western Mosquitofish",
    x_trim %in% c("CHNSC") ~ "Chinook Salmon - Spring",
    x_trim %in% c("CHNs") ~ "Chinook Salmon - Spring",
    x_trim %in% c("SPB", "spb") ~ "Spotted Bass",
    x_trim %in% c("Scp") ~ "Prickly Sculpin",
    x_trim %in% c("Res") ~ "Rainbow Trout (wild)",
    x_trim %in% c("Pink") ~ "Pink Salmon",
    x_trim %in% c("b") ~ NA_character_,

    TRUE ~ x_trim
  ) |>
    str_replace("^Unid\\b", "Unidentified")
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
    depth_1          = depth1,
    depth_2          = depth2,
    substrate_1      = hu_csubstrate,
    cover_1          = hu_ccover,
    stream_feature   = hu_cunit,
    species_code     = species_code,
    secchi           = sechi
  ) |>
  mutate(
    source           = "1997-2001",
    water_temp       = weathermetrics::fahrenheit.to.celsius(water_temp, round = 1),
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
    depth_1          = bs_depth_1_2,
    depth_2          = bs_depth_full,
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
         length, width, distance_out, depth_1, depth_2,
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
    depth_1      = bs_depth_1_2,
    depth_2      = bs_depth_full
  ) |>
  select(source, date, sample_id, seine_id, id, location, latitude, longitude, channel,
         gear_type, gear_size, survey_condition, water_temp, weather, secchi, flow,
         species, fork_length, lifestage, run, weight, count,
         length, width, distance_out, depth_1, depth_2,
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


# -------------------------------------------------------------------------
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
# TODO: add rivermile and lat/long of rivermile

all_seine_clean <- all_seine_combined |>
  filter(!gear_type %in% c("NETS", "EF_SE", "EF-SE")) |>
  mutate(
    sample_id = coalesce(sample_id, seine_id),
    gear_type = coalesce(gear_type, "SEIN")
    #n_hauls   = map_dbl(comments, extract_n_hauls)
  ) |>
  # Methods state a single "average depth of the haul" was recorded, but the
  # raw data has two point depths (depth_1, depth_2) plus, for 1997-2001 only,
  # the distances those points were taken at (depth_dist_1/2). depth_dist has
  # no equivalent in 2008+ data (depth there is fixed at half/full distance
  # out), so it can't be harmonized across eras - average the two depths into
  # one `depth` column per the methods text and drop the distance fields.
  mutate(depth = rowMeans(cbind(depth_1, depth_2), na.rm = TRUE)) |>
  # Methods define "seine area" as length, width, and average depth of the
  # haul, i.e. sample_area = length * width * depth. 1997-2001 already
  # supplies sample_area directly from the raw data; 2008+ data doesn't
  # include a pre-computed area, so derive it here from length/width/depth.
  mutate(sample_area = coalesce(sample_area, length * width * depth)) |>
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
      str_detect(species_clean, "^Chinook Salmon|^Steelhead Trout") ~ FALSE,
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
      str_detect(species_clean, "^Rainbow Trout|^Steelhead Trout") ~ "O. Mykiss",
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
         -depth_1, -depth_2, -depth_dist_1, -depth_dist_2)

