# Generate an EML metadata document for EDI publication
#
# This script uses hrlpub::make_eml_edi(), which wraps EMLassemblyline to
# produce an EML XML file. It reads:
#   - data tables from data/clean/
#   - metadata from publish/metadata/
#   - attribute definitions from publish/metadata/attributes/
# and writes the EML file to publish/eml/{edi_number}.xml.
#
# NOTE: This script only generates the EML metadata file locally. It does NOT
# submit anything to EDI. Run it, inspect the output XML, and verify the
# metadata looks correct before publishing (see publish/publish-data.R).
#
# Documentation:
#   - HRL publishing quickstart: https://lucy-dwr.github.io/hrl-docs/quickstart/publish-to-edi.html
#   - Worked example: https://github.com/Healthy-Rivers-and-Landscapes-Science/edi-hrl-pub-example
#
# Prerequisites before running:
#   1. Run scripts/setup.R once to restore the renv environment (installs
#      hrlpub and EMLassemblyline).
#   2. Complete all metadata templates in publish/metadata/ (see
#      publish/README.md for the full list). At minimum for this package:
#        abstract.txt, keywords, personnel/personnel.csv,
#        geographic_coverage.txt, methods.docx, taxonomic_coverage.txt,
#        custom_units.txt (if needed), intellectual_rights.txt, and the
#        attributes file named below.
#   3. Replace the edi_number placeholder below with a real reserved package
#      number before submitting. Reserve one at https://portal.edirepository.org/
#      (log in -> Tools -> Reserve a Package ID). There is no hrlpub function
#      for this step; it must be done through the EDI web portal.

library(hrlpub)
library(here)
# ==============================================================================
# Inputs ----
# ==============================================================================

# Data table(s) to include in the publication. Filenames only; make_eml_edi()
# reads from data/clean/ automatically. Each table must have a `date` column,
# which make_eml_edi() uses to set the temporal coverage.
data_file_names <- "all_seine_clean.csv"

# Attribute definition file(s), in the same order as data_file_names. Filenames
# only; make_eml_edi() reads from publish/metadata/attributes/. Convention is
# attributes_<data table name>.csv, so this matches the data file above.
# REVIEW: this file does not exist yet - copy
# publish/metadata/attributes/attributes_csv_template.csv to this name and fill
# in one row per column of all_seine_clean.csv (29 columns).
attributes_file_names <- "attributes_all_seine_clean.csv"

# ==============================================================================
# Metadata ----
# ==============================================================================

# REVIEW: draft title; confirm wording and that the 1997-2025 range is right.
# Dates in all_seine_clean.csv currently run 1997-01-21 to 2025-07-18, but the
# data come from three source tables (1997-2001, 2008-2014, 2015-2025), so
# there are gaps (2002-2007).
title <- "Feather River Beach Seine Fish Survey Data, 1997-2025"

# Short name and description for each data table, same order as data_file_names.
# REVIEW: draft wording.
table_names <- "Beach Seine Catch and Habitat Observations"
table_descriptions <- paste(
  "Fish catch (species, count, fork length, life stage) and associated sample",
  "habitat and water quality measurements for beach seine hauls on the lower",
  "Feather River. Each row is one species/length record from a seine haul;",
  "sample-level measurements are repeated across rows of the same sample."
)

# How often the package will be updated. Options: daily, weekly, monthly,
# annually, complete.
# TODO: "annually" if seining is ongoing and new years will be added;
# otherwise "complete".
maintenance <- "annually"

# EDI package number. The placeholder below ("edi.000.1") is safe to use for
# generating and inspecting EML locally. Before submitting to EDI, replace it
# with your reserved package number. Use "edi.XXXX.1" for a new package, or
# increment the version (e.g., "edi.XXXX.2") when updating an existing one.
edi_number <- "edi.000.1"

# ==============================================================================
# Generate EML ----
# ==============================================================================

# This call produces an EML XML file locally. It does not contact EDI.
# Open the output file in publish/eml/ to inspect the generated metadata. If
# EMLassemblyline reports issues, run EMLassemblyline::issues() for details.
# TODO: this doesn't work because it wants the data folder to be in the top level of
# the working directory. I need to manually adjust the function and then run it
# outside of hrlpub.

make_eml_edi <- function (data_file_names, attributes_file_names, title, table_names,
          table_descriptions, maintenance, edi_number)
{
  if (missing(data_file_names)) {
    stop("The 'data_file_names' argument is required.", call. = FALSE)
  }
  if (missing(attributes_file_names)) {
    stop("The 'attributes_file_names' argument is required.",
         call. = FALSE)
  }
  if (missing(title)) {
    stop("The 'title' argument is required.", call. = FALSE)
  }
  if (missing(maintenance)) {
    stop("The 'maintenance' argument is required.", call. = FALSE)
  }
  if (missing(edi_number)) {
    stop("The 'edi_number' argument is required.", call. = FALSE)
  }
  path_metadata <- here("edi-seine", "publish", "metadata")
  path_data <- here("edi-seine","data", "clean")
  path_eml <- here("edi-seine","publish", "eml")
  date_ranges <- map_dfr(data_file_names, function(file_name) {
    df <- read_csv(paste0(path_data, "/", file_name))
    tibble(min_date = min(df$date, na.rm = TRUE), max_date = max(df$date,
                                                                 na.rm = TRUE))
  })
  start_date <- min(date_ranges$min_date)
  end_date <- max(date_ranges$max_date)
  walk(attributes_file_names, function(file_name) {
    metadata_csv <- read_csv(here(path_metadata, "attributes",
                                  paste0(file_name)))
    names_without_ext <- sub("\\.[^.]*$", "", file_name)
    write.table(metadata_csv, file = here(path_metadata,
                                          paste0(names_without_ext, ".txt")), sep = "\t", row.names = FALSE,
                quote = FALSE)
  })
  personnel_csv <- read_csv(here(path_metadata, "personnel",
                                 "personnel.csv"))
  write.table(personnel_csv, file = here(path_metadata, "personnel.txt"),
              sep = "\t", row.names = F, quote = F)
  EMLassemblyline::make_eml(path = path_metadata, data.path = path_data,
                            eml.path = path_eml, dataset.title = title, temporal.coverage = c(start_date,
                                                                                              end_date), maintenance.description = maintenance,
                            data.table = data_file_names, data.table.name = table_names,
                            data.table.description = table_descriptions, user.id = Sys.getenv("EDI_USER_ID"),
                            user.domain = "EDI", package.id = edi_number)
  print("If issues are found, use EMLassemblyline::issues() for more information.")
}


make_eml_edi(
  data_file_names       = data_file_names,
  attributes_file_names = attributes_file_names,
  title                 = title,
  table_names           = table_names,
  table_descriptions    = table_descriptions,
  maintenance           = maintenance,
  edi_number            = edi_number
)

# ==============================================================================
# Taxonomic coverage helper (optional) ----
# ==============================================================================

# The seine data includes species observations, so publish/metadata/
# taxonomic_coverage.txt needs to be filled in (name, name_type, name_resolved,
# authority_system, authority_id). taxonomyCleanr can look up authority IDs.
# Run this interactively, review the result, and paste it into the template -
# do not leave it running as part of the script. `species` in
# all_seine_clean.csv is lower-case common names (e.g. "chinook salmon"), and
# includes non-fish/composite entries such as "sacramento pikeminnow or
# hardhead", which will need manual handling.
#
# species <- readr::read_csv(here::here("data", "clean", "all_seine_clean.csv")) |>
#   dplyr::distinct(species) |>
#   dplyr::pull(species)
#
# taxonomyCleanr::resolve_sci_taxa(
#   x = species,
#   data.sources = 3  # ITIS
# )
