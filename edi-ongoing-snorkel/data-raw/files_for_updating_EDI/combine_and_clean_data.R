# Script Purpose
# (1) pulls in data from the mdb files where snorkel data are stored.
# There are 2 database files (one for data pre-2004, and one for 2004-current)
# (2) does some initial cleaning and then combines data.

library(tidyverse)

# Read in cleaned pre-2004 data -------------------------------------------
# Read in data files from the earlier database (pre 2004) which are created in "data-prep-scripts/early_snorkel_db_pull.R"
cleaner_snorkel_metadata_early <- read_csv("data/cleaner_snorkel_metadata_early.csv")
cleaner_snorkel_data_early <- read_csv("data/cleaner_snorkel_data_early.csv")

# Pull and clean 2004-current data ----------------------------------------
# Note that the code below differs based on whether you are using a Mac or Windows
# The Windows code has difficulty reading from the .mdb file which required saving
# a copy of the database as .accdb which removed some permissions issues

operating_system <- ifelse(grepl("Windows", Sys.info()['sysname']), "windows", "mac")


if(operating_system == "windows") {
  library(RODBC)
  db_filepath <- here::here("data-raw", "db-files", "Snorkel_Revised_PC.accdb")
  con <- odbcConnectAccess2007(db_filepath)
  snorkel_obsv <- sqlFetch(con, "Observation") |> glimpse()
  write_csv(snorkel_obsv, "data-raw/db-tables/snorkel_observations.csv")

  # Other
  river_miles <- sqlFetch(con, "SnorkelSections_RiverMiles") |> glimpse()
  write_csv(river_miles, "data-raw/db-tables/river_miles_lookup.csv")
  # Lookup tables
  species_lookup <- sqlFetch(con, "SpeciesLU")  |> glimpse()
  lookup_cover <- sqlFetch(con, "ICoverLookUp") |> glimpse()
  lookup_o_cover <- sqlFetch(con, "OCoverLookUp") |> glimpse()
  lookup_substrate <- sqlFetch(con, "SubstrateCodeLookUp") |> glimpse()
  lookup_hydrology <- sqlFetch(con, "CGUCodeLookUp") |> glimpse()
  lookup_weather <- sqlFetch(con, "WeatherCodeLookUp") |> glimpse()
} else{
  library(Hmisc)
  db_filepath <- here::here("data-raw", "db-files", "Snorkel_Revised.mdb")
  mdb.get(db_filepath, tables = TRUE)

  snorkel_obsv <- mdb.get(db_filepath, "Observation") |> glimpse()
  write_csv(snorkel_obsv, "data-raw/db-tables/snorkel_observations.csv")

  snorkel_survey_metadata <- mdb.get(db_filepath, "Survey") |> glimpse()
  write_csv(snorkel_survey_metadata, "data-raw/db-tables/snorkel_survey_metadata.csv")

  # Other
  river_miles <- mdb.get(db_filepath, "SnorkelSections_RiverMiles") |> glimpse()
  write_csv(river_miles, "data-raw/db-tables/river_miles_lookup.csv")
  # Lookup tables
  species_lookup <- mdb.get(db_filepath, "SpeciesLU")  |> glimpse()
  lookup_cover <- mdb.get(db_filepath, "ICoverLookUp") |> glimpse()
  lookup_o_cover <- mdb.get(db_filepath, "OCoverLookUp") |> glimpse()
  lookup_substrate <- mdb.get(db_filepath, "SubstrateCodeLookUp") |> glimpse()
  lookup_hydrology <- mdb.get(db_filepath, "CGUCodeLookUp") |> glimpse()
  lookup_weather <- mdb.get(db_filepath, "WeatherCodeLookUp") |> glimpse()

  detach(package:Hmisc) # detach
}

# read in csvs -----------------------------------------------------------------
# need this step to deal with "labeled" column types which happens during the
# read in for Mac users

raw_snorkel_observations <- read_csv("data-raw/db-tables/snorkel_observations.csv")
raw_snorkel_survey_metadata <- read_csv("data-raw/db-tables/snorkel_survey_metadata.csv")
river_mile_lookup <- read_csv("data-raw/db-tables/river_miles_lookup.csv")

# Create helper function -------------------------------------------------------
# str_arrange created to arrange instream cover in alphabetical order
# reduces duplicates that are arranged differently
str_arrange <- function(x){
  x %>%
    stringr::str_split("") %>% # Split string into letters
    purrr::map(~sort(.) %>% paste(collapse = "")) %>% # Sort and re-combine
    as_vector() # Convert list into vector
}

# helps with removal of duplicates for LWD
remove_duplicates <- function(x) {
  str_replace_all(x, "(.)\\1+", "\\1")
}

# initial clean of site names
format_site_name <- function(string) {
  clean <-
    str_replace_all(string, "'", "") %>%
    str_replace_all("G-95", "G95") %>%
    str_replace_all("[^[:alnum:]]", " ") %>%
    trimws() %>%
    stringr::str_squish() %>%
    stringr::str_to_title()
}

# Join tables to lookup and clean --------------------------------------------
# Clean snorkel observations
cleaner_snorkel_observations <- raw_snorkel_observations |>
  janitor::clean_names() |>
  select(-comments) |> # keeping size class per comments; TODO check on lwd, remove comments
  left_join(species_lookup, by = c("species" = "SpeciesCode")) |>
  select(-species, -observer) |>
  rename(species = Species,
         observation_id = obs_id,
         survey_id = sid,
         channel_geomorphic_unit = hydrology_code,
         fork_length = est_size,
         depth = water_depth_m) |>
  mutate(run = case_when(species == "Chinook Salmon- Fall" ~ "fall",
                         species == "Chinook Salmon- Late Fall" ~ "late fall",
                         species %in% c("Chinook Salmon - Spring", "Chjnook Salmon- Spring") ~ "spring",
                         TRUE ~ NA_character_),
         clipped = case_when(species == "O. mykiss (not clipped)" ~ FALSE,
                             species == "O. Mykiss (clipped)" ~ TRUE,
                             species == "Chinook Salmon - Clipped" ~ TRUE,
                             T ~ NA),
         species = tolower(case_when(species %in% c("Chinook Salmon- Fall",
                                                    "Chinook Salmon- Late Fall",
                                                    "Chinook Salmon- Spring",
                                                    "Chjnook Salmon- Spring",
                                                    "Chinook Salmon - Clipped",
                                                    "Chinook salmon - Unknown",
                                                    "Chinook salmon - Tagged") ~ "Chinook Salmon",
                                     species %in% c("O. mykiss (not clipped)",
                                                    "O. mykiss (unknown)",
                                                    "O. Mykiss (Unknown)",
                                                    "O. mykiss (clipped)") ~ "O. Mykiss",
                                     species == "Unid Juvenile Sculpin" ~ "Unidentified Juvenile Sculpin",
                                     species == "Unid Juvenile Bass (Micropterus sp.)" ~ "Unidentified Juvenile Bass",
                                     species == "Unid Juvenile Lamprey" ~ "Unidentified Juvenile Lamprey",
                                     species == "Unid Juvenile Minnow" ~ "Unidentified Juvenile Minnow",
                                     species == "UNID Sunfish"   ~ "Unidentified Sunfish",
                                     species == "Unid Juvenile non-Micropterus Sunfish" ~ "Unidentified Juvenile non-Micropterus Sunfish",
                                     species == "Unid Juvenile Fish" ~ "Unidentified Juvenile Fish",
                                     species == "Sacramento Squawfish" ~ "Sacramento Pikeminnow",
                                     species %in% c("Sacramento Squawfish or Hardhead", "Pikeminnow/Hardhead") ~ "Sacramento Pikeminnow or hardhead",
                                     species == "NO FISH CAUGHT" ~ NA,
                                     TRUE ~ species)),
         channel_geomorphic_unit = case_when(channel_geomorphic_unit %in% c("Riffle Edgewater", "Riffle Margin") ~ "Riffle Margin",
                                             channel_geomorphic_unit %in% c("Glide Edgewater", "Glide Margin", "GM") ~ "Glide Margin",
                                             channel_geomorphic_unit %in% c("Backwater", "W") ~ "Backwater",
                                             channel_geomorphic_unit %in% c("Glide", "G") ~ "Glide",
                                             TRUE ~ channel_geomorphic_unit),
         instream_cover = ifelse(is.na(instream_cover), NA, str_arrange(toupper(instream_cover))),
         instream_cover = case_when(instream_cover == "VCDE" ~ "CDE", # V is not an instream cover code, remove
                                    instream_cover == "BEV" ~ "BE", # V is not an instream cover code, remove
                                    instream_cover == "CDEV" ~ "CDE", # V is not an instream cover code, remove
                                    instream_cover == "CC" ~ "C", # Duplicative, make just one
                                    instream_cover == "R" ~ NA, # R is not an instream cover code, remove
                                    instream_cover == "BG" ~ "B", # G is not an instream cover code, remove
                                    instream_cover == "0" ~ "A", # Assuming by 0 they mean "No Apparent Cover - A"
                                    TRUE ~ instream_cover),
         substrate = ifelse(is.na(substrate), NA, str_arrange(substrate)),
         substrate = as.numeric(case_when(substrate == "2344" ~ "234",
                                          substrate == "350" ~ "35",
                                          TRUE ~ substrate)),
         unit = case_when(unit == "32A" ~ "32", # cleaning up these units because they are not in the snorkel_section_river_miles table
                          unit == "329.5" ~ "329",
                          unit == "255A" ~ "255",
                          unit == "266A" ~ "266",
                          unit == "172B" ~ "172",
                          unit == "26A" ~ "26",
                          unit == "329B" ~ "329",
                          unit == "111A" ~ "111",
                          unit %in% c("274B", "274A") ~ "274",
                          unit == "448A" ~ "448",
                          unit == "271B" ~ "271",
                          unit %in% c("272A", "272B") ~ "272",
                          unit == "273B" ~ "273",
                          unit == "118A" ~ "118",
                          unit == "335B" ~ "335",
                          unit == "487B" ~ "487",
                          TRUE  ~ unit)) |>
  mutate(lwd_present  = ifelse(lwd > 0, "C", "")) |>
  mutate(instream_cover = case_when(lwd_present == "C" ~ paste0(lwd_present, instream_cover),
                                    TRUE ~ as.character(lwd_present)),
         instream_cover = remove_duplicates(instream_cover)) |>
  select(-lwd_present, -lwd) |>
  glimpse()

# Clean snorkel survey metadata
cleaner_snorkel_survey_metadata <- raw_snorkel_survey_metadata |>
  janitor::clean_names() |>
  select(
    -snorkelers,
    -comments,
    -shore_crew,
    -time_of_temperature,
    -snorkel_start_ttime,
    -snorkel_end_time
  ) |> # removing times because they are just dates(something lost in pull)
  rename(weather = weather_code) |>
  mutate(
    weather = case_when(
      weather %in% c("CLD", "CLDY") ~ "cloudy",
      weather %in% c("CLR (Hot)", "CLR/Hot", "Hot and CLR", "CLR Hot") ~ "clear and hot",
      weather %in% c("RAIN", "RAN", "CLD/RAIN", "LT RAIN", "CLD, Wind, Light Sprinkles") ~
        "precipitation",
      weather %in% c("CLR 95", "CLR") ~ "clear",
      weather %in% c("PT. CLDY", "CLR/CLD") ~ "partly cloudy",
      weather %in% c("sun", "SUN") ~ "sunny",
      weather == c("CLR WINDY") ~ "clear and windy",
      weather == c("WND") ~ "windy",
      weather == c("LT CLD/HAZE") ~ "hazy"
    ),
    # note that even though we don't use section_name and section_number we need it to add the appropriate section_type
    section_name = format_site_name(section_name),
    section_name = case_when(
      section_name %in% c(
        "Vance W",
        "Vance West",
        "Vance West Riffle",
        "Vance W Riffle",
        "Vance East",
        "Vance"
      ) ~ "Vance Riffle",
      section_name == "Eye" ~ "Eye Riffle",
      section_name == "Hatchery Side Ditch" ~ "Hatchery Ditch",
      section_name == "Hatchery Side Channel" ~ "Hatchery Riffle",
      section_name %in% c(
        "Gridley Side Channel",
        "Hidden Gridley Side Channel",
        "Gridley S C Riffle",
        "Gridley S C",
        "Gridley Sc"
      ) ~ "Gridley Riffle",
      section_name %in% c("Robinson", "Lower Robinson") ~ "Robinson Riffle",
      section_name == "Goose" ~ "Goose Riffle",
      section_name %in% c("Auditorium", "Upper Auditorium") ~ "Auditorium Riffle",
      section_name %in% c("Matthews", "Mathews", "Mathews Riffle") ~ "Matthews Riffle",
      section_name %in% c(
        "G95 Side Channel",
        "G95 Sc",
        "G95 West Side Channel",
        "G95 Side West",
        "G95 Side"
      ) ~ "G95",
      section_name %in% c("Alec Riffle", "Aleck") ~ "Aleck Riffle",
      section_name %in% c(
        "Lower Mcfarland",
        "Mcfarland",
        "Upper Mcfarland",
        "McFarland",
        "Mc Farland"
      ) ~ "McFarland",
      section_name %in% c("Bed Rock Riffle", "Bedrock Riffle", "Bedrock", "Bedrock Park") ~ "Bedrock Riffle",
      section_name == "Steep" ~ "Steep Riffle",
      section_name %in% c("Upper Hour Side Channel Rl", "Hour To Palm Side Rl")  ~ "Hour Side Channel",
      section_name %in% c("Keister", "Kiester", "Keister Riffle") ~ "Kiester Riffle",
      section_name == "Junkyard" ~ "Junkyard Riffle",
      section_name == "Gateway" ~ "Gateway Riffle",
      section_name %in% c(
        "Trailerpark",
        "Trailer Park",
        "Trailer Parkk",
        "Trailer Park Side Channel Pond"
      ) ~ "Trailer Park Riffle",
      section_name %in% c("Big Riffle Downstream Rl", "Bigriffle", "Big Riffle Bayou Rl") ~ "Big Riffle",
      section_name == "Section 2" ~ "Hatchery Ditch",
      section_name %in% c(
        "Hatchery Ditch And Moes",
        "Mo's Ditch",
        "Mo's Ditch",
        "Hatchery Ditch Moes Ditch",
        "Hatchery Side Channel Moes Ditch",
        "Upper Hatchery Ditch",
        "Hatchery Ditch Lower Moes Ditch Upper",
        "Moes",
        "Moes Ditch",
        "Hatchery Ditch And Moes Ditch",
        "Hatchery Side Channel And Moes Ditch",
        "Mo's Ditch",
        "Hatchery And Moes Ditches",
        "Hatchery Ditch Moes"
      ) ~ "Hatchery Ditch",
      # Because Mos is often lumped with Hatchey Ditch we can't separate these out
      section_name %in% c(
        "Hatchery And Moes Side Channels",
        "Hatchery Sc",
        "Moes Side Channel",
        "Moes Sc",
        "Hatchery Side Channel Moes",
        "Hatchery Side Ch Moes Side Ch",
        "Hatchery Side Channel And Moes",
        "Hatchery Side Channel And Moes Side Channel"
      ) ~ "Hatchery Riffle",
      .default = as.character(section_name)
    ),
    # section numbers come from map in 2012 report that numbers the sections
    section_number = case_when(
      section_name == "Aleck Riffle" ~ 8,
      section_name == "Auditorium Riffle" ~ 4,
      section_name == "Bedrock Park Riffle" ~ 5,
      #section_name == "Bedrock Riffle" ~ 10, not sure why we had this here
      section_name == "Big Riffle" ~ 17,
      section_name == "Eye Riffle" ~ 11,
      section_name == "G95" ~ 14,
      section_name == "Gateway Riffle" ~ 12,
      section_name == "Goose Riffle" ~ 16,
      section_name == "Gridley Riffle" ~ 19,
      section_name == "Hatchery Ditch" ~ 2,
      section_name == "Hatchery Riffle" ~ 1,
      section_name == "Junkyard Riffle" ~ 20,
      section_name == "Kiester Riffle" ~ 15,
      section_name == "Matthews Riffle" ~ 7,
      section_name == "McFarland" ~ 18,
      # section_name == "Mo's Ditch" ~ 3, # mos will always be lumped with hatchery ditch
      section_name == "Robinson Riffle" ~ 9,
      section_name == "Steep Riffle" ~ 10,
      section_name == "Trailer Park Riffle" ~ 6,
      section_name == "Vance Riffle" ~ 13,
      T ~ NA
    )
  ) |>

  glimpse()

# Combine the early and current snorkel data ------------------------------

# FlowWest created a lookup table that includes unit, section_name, section_number and section_type based on
# the map book (see "new_snork_maps.ppt") from Casey Campos. This lookup only includes units and sections
# that were permanent. Random sections/units are not included
# We just use section_type from this file
snorkel_built_lookup <- readxl::read_excel(here::here('data-raw', 'processed-tables', 'snorkel_built_lookup_table.xlsx')) |>
    select(-section_name) |>
    glimpse()

# Combine metadata (survey characteristics)
combined_snorkel_metadata <- bind_rows(cleaner_snorkel_metadata_early |>
                                         mutate(database = "historical"),
                                       cleaner_snorkel_survey_metadata |>
                                         mutate(database = "current")) |>
  select(-section_type) |>
  left_join(snorkel_built_lookup |>
              select(section_number, section_type) |> # joined to add the section_type
              distinct()) |>
  mutate(survey_id = paste0(survey_id, "_", database),
         section_type = ifelse(year(date) >= 2015 & is.na(section_type), "random", section_type),
         survey_type = ifelse(year(date) >= 2001 & is.na(survey_type), "unit", survey_type)) |>
  select(survey_id, date, survey_type, section_type, flow, weather, turbidity, temperature, visibility)

# Combine survey observations
combined_snorkel_observations <- bind_rows(cleaner_snorkel_data_early |>
                                             mutate(instream_cover = as.character(instream_cover),
                                                    database = "historical"
                                                    ),
                                           cleaner_snorkel_observations |>
                                             mutate(database = "current")
                                             ) |>
  mutate(survey_id = paste0(survey_id, "_", database)) |>
  filter(!unit %in% c("77-80", "86-89",
                      "104, 106, 112", "104 106  112",
                      "104 106 112", "446/449")) |>
  mutate(species = case_when(observation_id %in% c(16208, 16207) ~ 'chinook salmon', # change z.nada to chinook for these two observations per Casey comment
                             .default = as.character(species)),
         channel_geomorphic_unit = tolower(channel_geomorphic_unit),
         count = ifelse(is.na(count), 0, count)) |> # if count is NA, changed to zero
  # run is all NA so removed
  left_join(combined_snorkel_metadata |>
              select(survey_id, date)) |>
  filter(!is.na(date)) |> # filter out NA dates because not useful
  select(observation_id, survey_id, date, unit, count, species, fork_length, size_class, clipped, substrate, instream_cover, overhead_cover,
         channel_geomorphic_unit, depth, velocity) |>
  glimpse() # filtered out these messy units for now, alternatively we can see if casey can assign a non messy unit

# write csv for fish_observations
write_csv(combined_snorkel_observations, "data/fish_observations.csv")

combined_snorkel_metadata_na_rm <- combined_snorkel_metadata |>
  filter(!is.na(date))
# write csv for survey_characteristics
write_csv(combined_snorkel_metadata_na_rm, "data/survey_characteristics.csv")

# Locations lookup table - NOTE this is not expected to change over time

# Katie Lentz at DWR digitized the survey locations. Pulling this in and combining with information we have about location
digital_units <- read_csv("data-raw/processed-tables/Snorkel_Centroid_ExportFeatures_TableToExcel.csv")

full_location_lookup <- digital_units |>
                  mutate(unit = as.character(unit)) |>
  left_join(river_mile_lookup |> # join with the river mile lookup table from the revised snorkel db that includes the channel type (e.g. LFC/HFC)
              rename(unit = Snorkel.Sections,
                     channel_type = Channel,
                     river_mile = River.Mile)) |>
  select(unit, unit_sub_level, channel_type, river_mile, area_sq_m, latitude, longitude)

# write csv
write_csv(full_location_lookup, "data/locations_lookup.csv")
