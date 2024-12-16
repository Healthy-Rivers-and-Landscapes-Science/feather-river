# The goal of this script is to read in data from the mdb file in preparation for processing

library(RODBC)
library(tidyverse)
library(lubridate)

mini_snork_db <- odbcConnectAccess2007(here::here("data-raw", "MiniSnorkelDTB.mdb"))

# tables
all_fish_obs <- sqlFetch(mini_snork_db, "All fish observations")
phys_hab_available <- sqlFetch(mini_snork_db, "chn0 Phys Avail for All Fish")
phys_hab_available_minus_obs <- sqlFetch(mini_snork_db, "chn0 Phys Avail minus observations") # same number of obs/rows as above
phys <- sqlFetch(mini_snork_db, "PhysDataTbl")
rbt0_phys_available <- sqlFetch(mini_snork_db, "rbt0 Phys Avail for All Fish")
rbt1_phys_available <- sqlFetch(mini_snork_db, "rbt1 Phys Avail for All Fish")
rbt0_phys_available_minus_obs <- sqlFetch(mini_snork_db, "rbt0 Phys Avail minus observations") # same number of obs/rows as above
rbt1_phys_available_minus_obs <- sqlFetch(mini_snork_db, "rbt1 Phys Avail minus observations") # same number of obs/rows as above
fish_data <- sqlFetch(mini_snork_db, "FishDataTBL")
microhabitat <- sqlFetch(mini_snork_db, "MicroHabDataTbl")
microhabitat_rbt_use_2001 <- sqlFetch(mini_snork_db, "Microhabitat Avail and RBT Use 2001")
rbt_reach <- sqlFetch(mini_snork_db, "RBT Reach Data Flat 2001")
reach_summary <- sqlFetch(mini_snork_db, "Reach Habitat Summary")
canopy_cover <- sqlFetch(mini_snork_db, "CanopyCover")
comments <- sqlFetch(mini_snork_db, "Comments")

# lookups
cgu_code_lookup <- sqlFetch(mini_snork_db, "CGUCodeLookUp")
channel_lookup <- sqlFetch(mini_snork_db, "ChannelTypeLookUp")
instream_cover_lookup <- sqlFetch(mini_snork_db, "ICoverLookUp")
overhead_cover_lookup <- sqlFetch(mini_snork_db, "OCoverLookUp")
species_code_lookup <- sqlFetch(mini_snork_db, "SpeciesCodeLookUp")
weather_code_lookup <- sqlFetch(mini_snork_db, "WeatherCodeLookUp")
substrate_code_lookup <- sqlFetch(mini_snork_db, "SubstrateCodeLookUp")
# transect_canopy <- sqlFetch(mini_snork_db, "TransectCanopy") # empty