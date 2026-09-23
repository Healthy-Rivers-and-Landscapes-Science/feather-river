# This script reads in the raw drone redd survey data (the XY point data and
# the flight route mission shapefile paths) and is sourced by the cleaning
# script. No cleaning or transformation happens here.
library(tidyverse)
library(readxl)

# 2024 aerial (drone) redd survey XY data -----------------------------------

xy_data_path <- here::here("edi-redd", "drone-survey", "data", "raw",
                           "2024 Aerial Chinook Salmon Redd Survey XY Data.xlsx")

raw_lfc <- read_excel(xy_data_path, sheet = "LFC")
raw_hfc <- read_excel(xy_data_path, sheet = "HFC")

# 2025 aerial (drone) redd survey XY data ------------------------------------

# Same LFC/HFC sheet structure as 2024, but NOT byte-identical columns - see
# the rename in clean/clean-data.R for the two differences (date column name,
# and 2024 LFC's "Lattitude" typo that 2025 doesn't have).
xy_data_path_2025 <- here::here("edi-redd", "drone-survey", "data", "raw",
                                "2025 Aerial Chinook Salmon Redd Survey Data.xlsx")

raw_lfc_2025 <- read_excel(xy_data_path_2025, sheet = "LFC")
raw_hfc_2025 <- read_excel(xy_data_path_2025, sheet = "HFC")

# flight route mission shapefiles --------------------------------------------

mission_dir <- here::here("edi-redd", "drone-survey", "data", "raw",
                          "Aerial Chinook Salmon Redd Survey Flight Route Mission Shapefiles")
mission_files <- list.files(mission_dir, pattern = "\\.shp$", full.names = TRUE)

# 2024 & 2025 ground (walking) redd survey data ------------------------------

# Ground surveys are a separate, still-ongoing method alongside the drone
# survey - not a predecessor being replaced by it. Ground crews still walk
# sites the drone can't see into (e.g. Moe's Side Channel), and continue
# tracking redd size/substrate at a subset of other sites even where the
# drone also flies. Where both methods cover the same site, the same physical
# redd can be recorded by both - the two datasets are NOT a census when
# combined and are kept separate through cleaning rather than merged with
# drone_redd_clean.
raw_ground_2024 <- read_excel(here::here("edi-redd", "drone-survey", "data", "raw",
                                         "2024 Chinook Salmon Redd Survey Ground Survey Data.xlsx"))
raw_ground_2025 <- read_excel(here::here("edi-redd", "drone-survey", "data", "raw",
                                         "2025 Chinook Salmon Redd Survey Ground Survey Data.xlsx"))

# 2025 flight route schedule --------------------------------------------------

# NOT a normalized table - it's a wide, hand-formatted schedule with LFC and
# HFC side by side (columns 1-26 and 27-42), each block mixing "mission group"
# label rows (e.g. "Upper Cottonwood to Table Mountain", data cells all blank)
# with individual-location rows underneath, and repeating (date, redd total)
# column pairs per flight mission (#1 - #12). col_names = FALSE because the
# real header spans multiple rows in a way read_excel can't parse directly;
# see clean/clean-data.R for how this gets tidied, and the integration
# workflow notes for open questions about how to handle it.
raw_flight_schedule_2025 <- suppressMessages(read_excel(
  here::here("edi-redd", "drone-survey", "data", "raw",
             "2025 Aerial Chinook Salmon Redd Survey Flight Route Schedule.xlsx"),
  sheet = "Sheet1", col_names = FALSE
))

# 2024 flight route schedule --------------------------------------------------

# Not received from the data source yet (confirmed absent, not just
# unlooked-for). Placeholder path so that dropping the file in later - same
# name, same wide LFC/HFC-side-by-side layout as the 2025 schedule - is the
# only change needed; clean/clean-data.R already parses it conditionally.
flight_schedule_2024_path <- here::here("edi-redd", "drone-survey", "data", "raw",
                                        "2024 Aerial Chinook Salmon Redd Survey Flight Route Schedule.xlsx")

raw_flight_schedule_2024 <- if (file.exists(flight_schedule_2024_path)) {
  suppressMessages(read_excel(flight_schedule_2024_path, sheet = "Sheet1", col_names = FALSE))
} else {
  NULL
}
