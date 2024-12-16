library(EDIutils)
library(tidyverse)
library(EMLaide)
library(readxl)
library(EML)

datatable_metadata <-
  dplyr::tibble(filepath = c("data/survey_locations.csv",
                             "data/microhabitat_observations.csv"),
                attribute_info = c("data-raw/metadata/survey_locations_metadata.xlsx",
                                   "data-raw/metadata/microhabitat_metadata.xlsx"),
                datatable_description = c("Feather river mini snorkel survey locations data",
                                          "Feather river mini snorkel survey microhabitat data"),
                datatable_url = paste0("https://raw.githubusercontent.com/FlowWest/feather-mini-snorkel/main/data/", # make sure to use this type of link rather than "https://github.com/FlowWest/feather-mini-snorkel/blob/main/data/microhabitat_observations.csv"
                                       c("survey_locations.csv",
                                         "microhabitat_observations.csv")))

# other_entity_metadata <- list("file_name" = c("DWR_2004_SP_F10_3A_Final_Report.pdf"),
#                               "file_description" = c("Distribution and Habitat Use of Juvenile Steelhead and Other Fishes of the Lower Feather River"),
#                               "file_type" = c("PDF"),
#                               "physical" = create_physical("data-raw/metadata/DWR_2004_SP_F10_3A_Final_Report.pdf",
#                                                            data_url = "https://raw.githubusercontent.com/FlowWest/feather-mini-snorkel/main/data-raw/metadata/DWR_2004_SP_F10_3A_Final_Report.pdf")
# )
# other_entity_metadata$physical$dataFormat <- list("externallyDefinedFormat" = list("formatName" = "PDF"))
# save cleaned data to `data/`
excel_path <- "data-raw/metadata/feather_mini_snorkel_metadata.xlsx" 
sheets <- readxl::excel_sheets(excel_path)
metadata <- lapply(sheets, function(x) readxl::read_excel(excel_path, sheet = x))
names(metadata) <- sheets

abstract_docx <- "data-raw/metadata/abstract.docx"
methods_docx <- "data-raw/metadata/methods.md"

#edi_number <- reserve_edi_id(user_id = Sys.getenv("EDI_USER_ID"), password = Sys.getenv("EDI_PASSWORD"))
edi_number <- "edi.1705.2"
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
  #add_other_entity(other_entity_metadata)

# GO through and check on all units
custom_units <- data.frame(id = c("number of divers", "river mile", "decimal degrees", "decimal degrees", "count of fish", "NTU"),
                           unitType = c("dimensionless", "dimensionless", "dimensionless", "dimensionless","dimensionless","dimensionless"),
                           parentSI = c(NA, NA, NA, NA,NA,NA),
                           multiplierToSI = c(NA, NA, NA, NA,NA,NA),
                           description = c("number of divers", "river mile", "decimal degrees","decimal degrees","count of fish", "NTU"))


unitList <- EML::set_unitList(custom_units)

eml <- list(packageId = edi_number,
            system = "EDI",
            access = add_access(),
            dataset = dataset,
            additionalMetadata = list(metadata = list(unitList = unitList))
)
edi_number
EML::write_eml(eml, paste0(edi_number, ".xml"))
EML::eml_validate(paste0(edi_number, ".xml"))
# EMLaide::update_edi_package(Sys.getenv("EDI_USER_ID"),
#                             Sys.getenv("EDI_PASSWORD"),
#                             "edi.1705.1",
#                             "edi.1705.2.xml",
#                             environment = "production")
