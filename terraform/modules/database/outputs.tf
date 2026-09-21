# Outputs for the database module.
#
# To be added once the instance exists. Expected surface:
#   db_endpoint              — host:port for the app tier
#   db_port                  — 3306
#   db_name
#   db_credentials_secret_arn — what the app tier's IAM role is granted read
#                               access to
#
# Never output the password itself, not even marked sensitive.
