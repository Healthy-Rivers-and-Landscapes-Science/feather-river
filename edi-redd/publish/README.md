# publish/ - metadata and EML for the next edi.1802 version

Placeholders only, structured like the HRL EDI template
(https://github.com/FlowWest/hrl-edi-template; steps in the hrl-docs
"Publishing data to EDI" quickstart). Nothing is filled in yet.

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
