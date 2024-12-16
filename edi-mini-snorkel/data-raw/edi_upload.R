library(EMLaide)

# Validata package and resolve any issues
EMLaide::evaluate_edi_package(Sys.getenv("EDI_USER_ID"), Sys.getenv("EDI_PASSWORD"), paste0(edi_number, ".xml"))
View(report_df)

# Upload to staging to confirm package looks good
EMLaide::upload_edi_package(Sys.getenv("EDI_USER_ID"),
                            Sys.getenv("EDI_PASSWORD"),
                            paste0(edi_number, ".xml"),
                            environment = "staging")

# Upload to production
EMLaide::upload_edi_package(Sys.getenv("EDI_USER_ID"),
                            Sys.getenv("EDI_PASSWORD"),
                            paste0(edi_number, ".xml"),
                            environment = "production")

# EMLaide::update_edi_package(user_id = Sys.getenv("EDI_USER_ID"),
#                             password = Sys.getenv("EDI_PASSWORD"),
#                             eml_file_path = paste0(edi_number, ".xml"),
#                             existing_package_identifier = "edi.1705.1.xml",
#                             environment = "production")