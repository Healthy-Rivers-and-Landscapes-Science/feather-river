# edi-mini-snorkel

The goal of this repository is to clean and process data from the Feather River 
"mini snorkel" data collection effort for publication on the [Environmental Data Initiative](https://portal.edirepository.org/nis/mapbrowse?packageid=edi.1705.3).

### Mini Snorkel Data Collection Abstract

Understanding how fish presence is related to habitat features is useful in restoration planning and monitoring as better information about how fish use habitat may lead to more impactful restoration projects. The California Department of Water Resources (DWR), conducted a two-year study of microhabitat and mesohabitat in Feather River. The goal of this study was to identify relationships between habitat conditions (depth, substrate, velocity, and cover) and where juvenile Chinook salmon and steelhead occur. Snorkel surveys were conducted monthly March through August in 2001 and 2002 across 29 different sites, which were selected at random (13 in Low Flow Channel, and 16 in High Flow Channel). Each sampling section covered an area 25 meters long by 4 meters wide, running parallel to riverbank. These data were published to support the Healthy Rivers and Landscapes Science Program.

Note that this is not an ongoing data collection effort and does not need to be regulary maintained.

The data package published on EDI contains (use [`data-raw/edi_upload.R`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/blob/main/edi-mini-snorkel/data-raw/edi_upload.R)):

- the xml (most recent xml is [`edi.1705.3.xml`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/blob/main/edi-mini-snorkel/edi.1705.3.xml), prepared using [`data-raw/make_metadata_xml.R`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/blob/main/edi-mini-snorkel/data-raw/make_metadata_xml.R)
- metadata (see [`data-raw/metadata`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/tree/main/edi-mini-snorkel/data-raw/metadata))
- csv (see [`data`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/tree/main/edi-mini-snorkel/data))

The data files were prepared using [`data-raw/prepare_data.Rmd`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/blob/main/edi-mini-snorkel/data-raw/prepare_data.Rmd) which sources a query file to
extract data from the appropriate databases (saved in the [`databases`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/tree/main/edi-mini-snorkel/data-raw/databases) folder and extracted tables are saved in [`database-tables`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/tree/main/edi-mini-snorkel/data-raw/database-tables)).

Exploratory data analysis and QC was performed and retained in the [`qc`](https://github.com/Healthy-Rivers-and-Landscapes-Science/feather-river/tree/main/edi-mini-snorkel/data-raw/qc) folder.

