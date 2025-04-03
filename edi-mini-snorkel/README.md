# edi-mini-snorkel

The goal of this repository is to clean and process data from the Feather River 
"mini snorkel" data collection effort for publication on the [Environmental Data Initiative](https://portal.edirepository.org/nis/mapbrowse?packageid=edi.1705.3).

Note that this is not an ongoing data collection effort and does not need to be regulary maintained.

The data package published on EDI contains (use `data-raw/edi_upload.R`):

- the xml (most recent xml is `edi.1705.3.xml`, prepared using `data-raw/make_metadata_xml.R`)
- metadata (see `data-raw/metadata`)
- csv (see `data`)

The data files were prepared using `data-raw/prepare_data.Rmd` which sources a query file to
extract data from the appropriate databases (saved in the `databases` folder and extracted tables are saved in `database-tables`).

Exploratory data analysis and QC was performed and retained in the `qc` folder.

