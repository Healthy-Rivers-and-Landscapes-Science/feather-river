# mini-snorkel-analysis

This folder contains exploratory data analysis, habitat modeling, and cluster analysis using the Feather River mini snorkel dataset and ongoing snorkel dataset. The goal of this work is to understand relationships between habitat conditions and juvenile Chinook salmon and steelhead presence in the Feather River to support restoration planning under the Healthy Rivers and Landscapes (HR&L) program.

## Source Data

Data are pulled from the Environmental Data Initiative (EDI) using [`data-raw/pull_from_edi.R`](data-raw/pull_from_edi.R):

- **Mini snorkel survey** (2001–2002): [Kurth, R. 2024 — edi.1705.2](https://portal.edirepository.org/nis/mapbrowse?packageid=edi.1705.2) — microhabitat and mesohabitat observations across 29 sites in the Low Flow and High Flow channels
- **Ongoing snorkel survey**: [Campos, C. 2024 — edi.1764.1](https://portal.edirepository.org/nis/mapbrowse?packageid=edi.1764.1) — 25+ years of snorkel survey data
- **Redd survey data**: [Cook, C. 2025 — edi.1802.2](https://portal.edirepository.org/nis/metadataviewer?packageid=edi.1802.2) — Chinook salmon redd surveys on the Feather River

Raw data files used in analyses are stored in [`data-raw/`](data-raw/).

## Analysis

### Overview

[`analysis/analysis_overview.Rmd`](analysis/analysis_overview.Rmd) provides a high-level summary of both the mini snorkel and ongoing snorkel datasets, including fish observations, depth, velocity, substrate, cover, and channel geomorphic unit distributions.

### Cluster Analysis

[`analysis/mini_snorkel_cluster_analysis.Rmd`](analysis/mini_snorkel_cluster_analysis.Rmd) explores the distributions of and correlations between key habitat variables (depth, velocity, cover, substrate) and tests clustering methods to identify habitat types. Feather River is used as a case study with the goal of developing a workflow applicable across other locations.

### Habitat Suitability Modeling

Species-specific binary logistic regression models (mixed effects) were developed to assess the significance of cover, substrate, depth, and velocity on fish presence/absence:

- [`analysis/feather_river_cover_analysis_salmon.Rmd`](analysis/feather_river_cover_analysis_salmon.Rmd) — Chinook salmon
- [`analysis/feather_river_cover_analysis_steelehead.Rmd`](analysis/feather_river_cover_analysis_steelehead.Rmd) — steelhead

### Model Comparisons

[`analysis/model_comparisons.Rmd`](analysis/model_comparisons.Rmd) compares FlowWest's Chinook and steelhead models to the [FERC 2004 report](https://netorg629193.sharepoint.com/sites/VA-FeatherRiver/Shared%20Documents/Forms/AllItems.aspx?id=%2Fsites%2FVA%2DFeatherRiver%2FShared%20Documents%2FResources%2FFeather%20River%20Reports%2F04%2D28%2D04%5Fatt%5F10%5Ff10%5F3A%5Fsteelhead%5Fhab%5Fuse%2Epdf&parent=%2Fsites%2FVA%2DFeatherRiver%2FShared%20Documents%2FResources%2FFeather%20River%20Reports&p=true&ga=1) that analyzed the same mini snorkel dataset.

### Additional Analyses

- [`analysis/occupancy_model.Rmd`](analysis/occupancy_model.Rmd) and [`analysis/occupancy_model_v2.Rmd`](analysis/occupancy_model_v2.Rmd) — exploratory occupancy modeling using the mini snorkel data with different grouping approaches
- [`analysis/snorkel_data_visualizations.Rmd`](analysis/snorkel_data_visualizations.Rmd) — additional data visualizations
- [`analysis/outmigration_eda.qmd`](analysis/outmigration_eda.qmd) — exploratory data analysis of outmigration data
- [`analysis/analysis-figures.R`](analysis/analysis-figures.R) — script for generating summary figures

Output figures are saved in [`figures/`](figures/) and created in [`analysis/analysis-figures.R`](analysis/analysis-figures.R)

### Last updated
Maddee Wiggins 6/18/2026
