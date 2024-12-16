# The goal of this script is to read in data from the mdb file in preparation for processing

library(tidyverse)
library(knitr)
library(Hmisc)
library(lubridate)

mini_snork_db <- here::here("data-raw", "databases",  "MiniSnorkelDTB.mdb")
mdb.get(mini_snork_db, tables = T)

ck_db <- here::here("data-raw", "databases",  "FR_S_and_S_Tables.mdb")
mdb.get(ck_db, tables = T)

snork_micro <- mdb.get(ck_db, tables = "SnorkMicrohabitat")
write_csv(snork_micro, here::here("data-raw", "databases", "SnorkMicrohabitat.csv"))
snork <- mdb.get(ck_db, tables = "SnorkObservationsTBL")
# tables
all_fish_obs <- mdb.get(mini_snork_db, tables = "All fish observations") |> glimpse()
write_csv(all_fish_obs, here::here("data-raw/database-tables/all_fish_obs.csv"))
all_fish_obs <- read_csv(here::here("data-raw/database-tables/all_fish_obs.csv")) |> glimpse()

# phys_hab_available <- mdb.get(mini_snork_db, tables = "chn0 Phys Avail for All Fish") |> glimpse() # subset of all_fish_obs, physical habitat associated with grid chinook salmon found
# seems like the same
# phys_hab_available_minus_obs <- mdb.get(mini_snork_db, tables = "chn0 Phys Avail minus observations") # same number of obs/rows as above
location_table <- mdb.get(mini_snork_db, tables = "PhysDataTbl")
write_csv(location_table, here::here("data-raw/database-tables/location_table.csv"))
location_table <- read_csv(here::here("data-raw/database-tables/location_table.csv")) |> glimpse()
# rbt0_phys_available <- mdb.get(mini_snork_db, tables = "rbt0 Phys Avail for All Fish") |> glimpse() # age 0 rbt data
# rbt1_phys_available <- mdb.get(mini_snork_db, tables = "rbt1 Phys Avail for All Fish") |> glimpse() # age 1 rbt data
# rbt0_phys_available_minus_obs <- mdb.get(mini_snork_db, tables = "rbt0 Phys Avail minus observations") # same number of obs/rows as above
# rbt1_phys_available_minus_obs <- mdb.get(mini_snork_db, tables = "rbt1 Phys Avail minus observations") # same number of obs/rows as above
fish_data <- mdb.get(mini_snork_db, tables = "FishDataTBL") |> glimpse()
write_csv(fish_data, here::here("data-raw/database-tables/fish_data.csv"))

fish_data <- read_csv(here::here("data-raw/database-tables/fish_data.csv")) |> glimpse()


# more than columns of above compareable data
# could this be the no detection data
microhabitat <- mdb.get(mini_snork_db, tables = "MicroHabDataTbl") |> glimpse()
# microhabitat_rbt_use_2001 <- mdb.get(mini_snork_db, tables = "Microhabitat Avail and RBT Use 2001")
# rbt_reach <- mdb.get(mini_snork_db, tables = "RBT Reach Data Flat 2001") |> glimpse()
reach_summary <- mdb.get(mini_snork_db, tables = "Reach Habitat Summary") |> glimpse()
canopy_cover <- mdb.get(mini_snork_db, tables = "CanopyCover") |> glimpse() # ASK about this one
write_csv(canopy_cover, here::here("data-raw/database-tables/canopy_cover_db_table.csv"))
comments <- mdb.get(mini_snork_db, tables = "Comments") |> glimpse()

# lookups
cgu_code_lookup <- mdb.get(mini_snork_db, tables = "CGUCodeLookUp")
channel_lookup <- mdb.get(mini_snork_db, tables = "ChannelTypeLookUp")
instream_cover_lookup <- mdb.get(mini_snork_db, tables = "ICoverLookUp")
overhead_cover_lookup <- mdb.get(mini_snork_db, tables = "OCoverLookUp")
species_code_lookup <- mdb.get(mini_snork_db, tables = "SpeciesCodeLookUp")
weather_code_lookup <- mdb.get(mini_snork_db, tables = "WeatherCodeLookUp")
substrate_code_lookup <- mdb.get(mini_snork_db, tables = "SubstrateCodeLookUp")
# transect_canopy <- mdb.get(mini_snork_db, tables = "TransectCanopy") # empty

library(Hmisc)
seine_db <- here::here("data-raw", "databases",  "FR_S_and_S_Oroville.mdb")
mdb.get(seine_db, tables = T)

# has no dates
juv_hab <- mdb.get(seine_db, tables = "Juv Steelhead Hab Table") |> glimpse()
snork_survey <- mdb.get(seine_db, tables = "SnorkSurveyTBL") |> glimpse()
snork_obs <- mdb.get(seine_db, tables = "SnorkObservationsTBL") |> glimpse()


# add in 2002 database table ----------------------------------------------
mini_snork_db_2002 <- here::here("data-raw", "databases",  "minisnorkdb3.mdb")
mdb.get(mini_snork_db_2002, tables = T)

## tables
all_fish_obs_2002 <- mdb.get(mini_snork_db_2002, tables = "FishDataTBL") |>  labelled::remove_labels()  |> glimpse()
#write_csv(all_fish_obs_2002, "data-raw/database-tables/all_fish_obs_2002.csv")

location_table_2002 <- mdb.get(mini_snork_db_2002, tables = "PhysDataTbl") |> 
  labelled::remove_labels() |> 
  glimpse()
#write_csv(location_table_2002, "data-raw/database-tables/location_table_2002.csv")

fish_data_2002 <- mdb.get(mini_snork_db_2002, tables = "FishDataTBL") |> 
  labelled::remove_labels() |> 
  glimpse()
#write_csv(fish_data_2002, "data-raw/database-tables/fish_data_2002.csv")

microhabitat_2002 <- mdb.get(mini_snork_db_2002, tables = "MicroHabDataTbl") |> 
  labelled::remove_labels() |> 
  glimpse()

species_code_lookup_2002 <- mdb.get(mini_snork_db_2002, tables = "SpeciesCodeLookUp") |> 
  labelled::remove_labels() |> 
  glimpse()

location_table_2002 <- mdb.get(mini_snork_db_2002, tables = "PhysDataTbl") |> 
  labelled::remove_labels() |> 
  glimpse()

weather_code_lookup_2002 <- mdb.get(mini_snork_db_2002, tables = "WeatherCodeLookUp") |> 
  labelled::remove_labels() |> glimpse()

channel_lookup_2002 <- mdb.get(mini_snork_db_2002, tables = "ChannelTypeLookUp") |> 
  labelled::remove_labels() |> glimpse()

cgu_code_lookup_2002 <- mdb.get(mini_snork_db_2002, tables = "CGUCodeLookUp") |> 
  labelled::remove_labels() |> glimpse()








