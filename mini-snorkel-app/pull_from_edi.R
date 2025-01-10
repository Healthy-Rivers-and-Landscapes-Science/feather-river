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
write_csv(mini_locations_raw, "mini-snorkel-app/mini_locations_raw.csv")
raw <- read_data_entity(packageId = "edi.1705.2", entityId = res$entityId[2])
mini_fish_raw <- read_csv(file = raw)
write_csv(mini_fish_raw, "mini-snorkel-app/mini_fish_raw.csv")
