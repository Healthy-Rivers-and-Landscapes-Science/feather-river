# Script to run the wrapper function that uses EMLassemblyline workflow to make
# EML which is required for publishing on EDI
# (template: https://github.com/FlowWest/hrl-edi-template)

# TODO insert link to documentation

# TODO code to install hrlpub

# TODO: one data file and one attributes file per table. Tables (and whether
# the drone tables / flight schedule / shapefiles are published) depend on the
# decisions still open with Chris - see publish/README.md
# TODO: make_eml_edi() reads data files from data/clean/ in the template;
# confirm whether that also works for data/publish/ here
make_eml_edi(data_file_names = c("redd_observation_w_zeros.csv",
                                 "survey_site_dates.csv",
                                 "survey_site_area.csv",
                                 "INSERT DRONE REDD OBSERVATION FILE NAME",
                                 "INSERT DRONE FLIGHT SCHEDULE FILE NAME"),
             attributes_file_names = c("attributes_redd_observation_w_zeros.csv",
                                       "attributes_survey_site_dates.csv",
                                       "attributes_survey_site_area.csv",
                                       "attributes_drone_redd_observation.csv",
                                       "attributes_drone_flight_schedule.csv"),
             title = "Redd survey data of Chinook salmon in the Feather River",
             maintenance = "ongoing", # TODO: confirm format hrlpub expects (1802.4: status ongoing, update_frequency annually)
             edi_number = "INSERT EDI NUMBER") # TODO: next version of edi.1802
