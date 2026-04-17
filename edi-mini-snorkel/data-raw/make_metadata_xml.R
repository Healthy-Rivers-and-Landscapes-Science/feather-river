library(EDIutils)
library(tidyverse)
library(EMLaide)
library(readxl)
library(EML)

datatable_metadata <-
  dplyr::tibble(filepath = c("edi-mini-snorkel/data/survey_locations.csv",
                             "edi-mini-snorkel/data/microhabitat_observations.csv"),
                attribute_info = c("edi-mini-snorkel/data-raw/metadata/survey_locations_metadata.xlsx",
                                   "edi-mini-snorkel/data-raw/metadata/microhabitat_metadata.xlsx"),
                datatable_description = c("Feather river mini snorkel survey locations data",
                                          "Feather river mini snorkel survey microhabitat data"),
                datatable_url = paste0("https://raw.githubusercontent.com/Healthy-Rivers-and-Landscapes-Science/feather-river/main/edi-mini-snorkel/data/", # make sure to use this type of link rather than "https://github.com/FlowWest/feather-mini-snorkel/blob/main/data/microhabitat_observations.csv"
                                       c("survey_locations.csv",
                                         "microhabitat_observations.csv")))

excel_path <- "edi-mini-snorkel/data-raw/metadata/feather_mini_snorkel_metadata.xlsx"
sheets <- readxl::excel_sheets(excel_path)
metadata <- lapply(sheets, function(x) readxl::read_excel(excel_path, sheet = x))
names(metadata) <- sheets

abstract_docx <- "edi-mini-snorkel/data-raw/metadata/abstract.docx"
methods_docx <- "edi-mini-snorkel/data-raw/metadata/methods.md"

#edi_number <- reserve_edi_id(user_id = Sys.getenv("EDI_USER_ID"), password = Sys.getenv("EDI_PASSWORD"))
edi_number <- "edi.1705.4"
dataset <- list() %>%
  add_pub_date() %>%
  add_title(metadata$title) %>%
  add_personnel(metadata$personnel) %>%
  add_keyword_set(metadata$keyword_set) %>%
  add_abstract(abstract_docx) %>%
  add_license(metadata$license) %>%
  add_method(methods_docx) %>%
  add_maintenance(metadata$maintenance) %>%
  add_project(metadata$funding) %>%
  add_coverage(metadata$coverage, metadata$taxonomic_coverage) %>%
  add_datatable(datatable_metadata)

# GO through and check on all units
custom_units <- data.frame(id = c("number of divers", "river mile", "decimal degrees", "decimal degrees", "count of fish"),
                           unitType = c("dimensionless", "dimensionless", "dimensionless", "dimensionless","dimensionless"),
                           parentSI = c(NA, NA, NA, NA,NA),
                           multiplierToSI = c(NA, NA, NA, NA,NA),
                           description = c("number of divers", "river mile", "decimal degrees","decimal degrees","count of fish"))


unitList <- EML::set_unitList(custom_units)

eml <- list(packageId = edi_number,
            system = "EDI",
            access = add_access(),
            dataset = dataset,
            additionalMetadata = list(metadata = list(unitList = unitList))
)
edi_number
EML::write_eml(eml, paste0("edi-mini-snorkel/", edi_number, ".xml"))
EML::eml_validate(paste0("edi-mini-snorkel/", edi_number, ".xml"))
EMLaide::evaluate_edi_package(Sys.getenv("EDI_USER_ID"),
                              Sys.getenv("EDI_PASSWORD"),
                              paste0("edi-mini-snorkel/", edi_number, ".xml"))

 # EMLaide::update_edi_package(Sys.getenv("EDI_USER_ID"),
                             # Sys.getenv("EDI_PASSWORD"),
                             # "edi.1705.3",
                             # paste0("edi-mini-snorkel", edi_number, ".xml"),
                             # environment = "production")
