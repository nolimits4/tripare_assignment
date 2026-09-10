# Partial backend configuration.
#
# Prod state lives in its own bucket and lock table, separate from dev, so a
# mistake in one environment cannot corrupt the other. Supply them at init time:
#
#   terraform init -backend-config=backend.hcl
#
# Reviewers who only want fmt/validate/plan can skip remote state entirely:
#
#   terraform init -backend=false
#
terraform {
  backend "s3" {
    key     = "hotelapp/prod/terraform.tfstate"
    encrypt = true
  }
}
