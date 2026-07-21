# This script reads in the raw access database files and is then sourced in the cleaning script
library(tidyverse)
library(readxl)

# pull 1997-2001 -------------------------------------------------------

raw_1997 <- read_excel(here::here("edi-seine","data", "raw", "JPE_SR_all_seine_individuals1997-2001.xlsx"))

# pull 2008-2014 -------------------------------------------------------

raw_2008 <- read_excel(here::here("edi-seine","data", "raw", "all_fields_seine_2008-2014.xlsx"))

# pull 2015-2025 -------------------------------------------------------

db_path <- here::here("edi-seine","data", "raw", "FR Seining_2015_ 2025.accdb")

list_access_tables <- function(db_path) {
  system2("mdb-tables", args = c("-1", shQuote(db_path)), stdout = TRUE)
}

read_access_table <- function(db_path, table_name) {
  output <- system2(
    "mdb-export",
    args = c(shQuote(db_path), shQuote(table_name)),
    stdout = TRUE
  )
  read_csv(paste(output, collapse = "\n"), show_col_types = FALSE)
}

tables <- list_access_tables(db_path)
tables <- tables[tables != "Switchboard Items"]

table_list <- tables |>
  set_names() |>
  map(~ read_access_table(db_path, .x))

list2env(
  setNames(table_list, snakecase::to_snake_case(names(table_list))),
  envir = .GlobalEnv
)
