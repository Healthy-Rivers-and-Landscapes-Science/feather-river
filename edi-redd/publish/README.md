# publish/ - metadata and EML for the next edi.1802 version

Structured like the HRL EDI template
(https://github.com/FlowWest/hrl-edi-template; steps in the hrl-docs
"Publishing data to EDI" quickstart). **Draft content is filled in** (methods,
abstract, keywords, personnel, coverage, license, attribute dictionaries); it
needs review. Previous version's metadata is in `metadata/edi.1802.4/`.

## Draft decisions / things to check

- Geographic bounding box was recomputed from all redd points (2014-2025):
  W -121.64133, E -121.55047, S 39.372913, N 39.518005. The 1802.4 workbook had
  a different box labelled "Feather River Rotary Screw Trap" (likely a copy-paste
  error); the old attribute ranges also showed one longitude of -127.64.
- Temporal coverage (2014-09-09 to 2025-11-18) is not in a file; confirm
  hrlpub derives it from the data.
- Units use the EML dictionary (`number` for redd/salmon counts), so
  `custom_units.txt` is empty.
- `personnel.txt` and `personnel/personnel.csv` hold the same people (from the
  1802.4 workbook: Chris Cook creator/contact, Casey Campos PI); no ORCIDs.
- Taxonomic coverage lists only the scientific name; authority columns blank.
- Attribute files for the two drone tables use the column names a published
  file would have (`location` = EDI name, `number_redds`), not the
  `data/clean/` names (`edi_location`, `n_redds`); rename when building them.
- `mission_label` definition is a guess - confirm with Chris.

## Where things live

| Path | Holds | Replaces (edi.1802.4, in `archive_of_edi_1802.4_and_earlier/data-raw/metadata/`) |
|------|-------|-----------|
| `metadata/abstract.txt` | abstract | `abstract.docx` |
| `metadata/methods.docx` | methods (add the drone/UAV methods) | `methods.docx`, `methods.md` |
| `metadata/keywords.txt` | keywords (must include `Healthy Rivers and Landscapes`) | `feather_redd_project_metadata.xlsx` (keyword_set) |
| `metadata/personnel.txt`, `metadata/personnel/personnel.csv` | creators / contacts / funding | `feather_redd_project_metadata.xlsx` (personnel, funding) |
| `metadata/geographic_coverage.txt` | bounding box | `feather_redd_project_metadata.xlsx` (coverage) |
| `metadata/taxonomic_coverage.txt` | Chinook salmon | `feather_redd_project_metadata.xlsx` (taxonomic_coverage) |
| `metadata/intellectual_rights.txt` | license | `feather_redd_project_metadata.xlsx` (license) |
| `metadata/custom_units.txt` | units outside the EML dictionary | `custom_units` in `make_metadata_xml.R` |
| `metadata/attributes/attributes_<table>.csv` | data dictionary per table | `feather_redd_*_metadata.xlsx` |
| `eml/` | generated EML | `edi.1802.N.xml` |
| `make-eml.R`, `publish-data.R` | build and submit | `make_metadata_xml.R` |

Temporal coverage and other fields in the project metadata workbook (title,
maintenance) have no template file; they are arguments in `make-eml.R`.

## Attribute files (one per table)

- `attributes_redd_observation_w_zeros.csv` - existing table, plus 2024-2025 ground rows
- `attributes_survey_site_dates.csv` - existing table (needs 2024-2025 ground survey weeks)
- `attributes_survey_site_area.csv` - existing table (new sites, if any)
- `attributes_drone_redd_observation.csv` - new; pending decision (separate drone table?)
- `attributes_drone_flight_schedule.csv` - new; pending decision (publish the schedule?)
- Flight route / ground survey polygons: spatial entities, no attributes file;
  pending decision.

Delete the placeholders for tables that are not published.
