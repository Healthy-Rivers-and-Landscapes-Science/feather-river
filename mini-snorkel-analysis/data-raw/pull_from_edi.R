# Pull snorkel data from EDI
library(EDIutils)
# Ongoing snorkel survey data
res <- read_data_entity_names(packageId = "edi.1764.1")
raw <- read_data_entity(packageId = "edi.1764.1", entityId = res$entityId[1])
survey_raw <- read_csv(file = raw)
raw <- read_data_entity(packageId = "edi.1764.1", entityId = res$entityId[2])
locations_lookup_raw <- read_csv(file = raw)
raw <- read_data_entity(packageId = "edi.1764.1", entityId = res$entityId[3])
fish_raw <- read_csv(file = raw)

# Mini snorkel data
res <- read_data_entity_names(packageId = "edi.1705.2")
raw <- read_data_entity(packageId = "edi.1705.2", entityId = res$entityId[1])
mini_locations_raw <- read_csv(file = raw)
raw <- read_data_entity(packageId = "edi.1705.2", entityId = res$entityId[2])
mini_fish_raw <- read_csv(file = raw)

# feather river redd data
res <- read_data_entity_names(packageId = "edi.1802.2")
raw <- read_data_entity(packageId = "edi.1802.2", entityId = res$entityId[1])
redd_data <- read_csv(file = raw)
#write_csv(redd_data, "data-raw/redd_data.csv")
