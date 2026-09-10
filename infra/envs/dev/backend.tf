# Partial backend configuration.
#
# The bucket and lock table are intentionally left out of source control so the
# same code works against different accounts. Supply them at init time:
#
#   terraform init -backend-config=backend.hcl
#
# Reviewers who only want fmt/validate/plan can skip remote state entirely:
#
#   terraform init -backend=false
#
terraform {
  backend "s3" {
    key     = "hotelapp/dev/terraform.tfstate"
    encrypt = true
  }
}
