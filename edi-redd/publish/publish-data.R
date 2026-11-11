# Script used to publish data to EDI
# (template: https://github.com/FlowWest/hrl-edi-template)

# TODO insert link to documentation

# TODO code to install hrlpub

# TODO: edi.1802 already exists, so this is an update of the existing package
publish_data_edi(path_eml_file = "INSERT FILE PATH",
                 publish_type = "OPTIONS ARE: new, update",
                 edi_number = "INSERT EDI NUMBER",
                 publish_environment = "staging")
