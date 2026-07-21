# Steps to publish data - DRAFT (may move to root README)

1. Connect to data

- Manual: Download your data (e.g. Access, Excel, etc.) and save this file in
`data-raw`
- API (ideal): Establish a direct connection to your database. 

2. Read in data

`read-data.R`

- Manual: Read in the data file saved in `data-raw`
- API (ideal): Read in data by connecting to your database

3. QC and process data

Create a vignette or R script to do this. If this workflow is new, recommend 
starting with an R script to ensure the steps are functional and then this can
be moved over to a vignette

Save the cleaned, final dataset in `data` (if this repository is going to be
a data package) and `data-raw/data_objects` (development of metadata is set up
to pull final data to be published from this folder)

4. Prepare metadata

4a. Manually complete metadata templates

`data-raw/metadata_templates` contains templates that need to be filled in. The
following need to be manually filled in.

- **abstract**: Add your abstract to the `abstract.txt` file
- **attributes**: Each dataset needs a data dictionary. These will ultimately be
saved as .txt files but we recommend filling in the csv template (`data-raw/metadata_templates/attributes_csv_template`)
- **custom units (as needed)**: Allowable units are defined
[here](https://eml.ecoinformatics.org/schema/eml-unittypedefinitions_xsd#otherUnitType). 
Other units need to be defined in the `custom_units.text` document.
- **keywords**: Add keywords to `keywords.txt`.
- **methods**: Add your methods to the `methods.docx` file
- **personnel**: Describes the personnel and funding sources involved in the creation
of the data. See [EMLassemblyline docs](https://ediorg.github.io/EMLassemblyline/articles/edit_tmplts.html)
for more details on roles. "creator" and "contact" roles are required. Similar to
attributes, these will ultimately be saved as .txt files but we recommend filling
in the csv template (`data-raw/metadata_templates/personnel_csv_template`) and
save as `personnel.csv`
- **taxonomic coverage**: If data are collected on species you will need to fill in
this metdata. You can use the `taxonomyCleanr` package to help find the `authority_id` 
for species in your dataset. Helper code is included in `make-eml.R`

4b. Finish creating metadata using `make-eml.R` and make EML

Some metadata can be automatically created using the `EMLassemblyline` package.
Helper code is included in `make-eml.R`. Fill in the information needed at the 
top of `data-raw/make-eml.R` then run this script to generate the EML document
needed to publish. 

Note that you will need an EDI account. If you do not have one, contact 
support@edirepository.org to create an account.

5. Publish data on EDI

Use `publish-data.R` to upload or update your data package on EDI. New packages
utilize the `upload` API function whereas updating existing packages utilize the
`update` API function. When updating a package you will need to know the existing
EDI package ID.

