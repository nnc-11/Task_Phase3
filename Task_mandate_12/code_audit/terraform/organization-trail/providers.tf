provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "techx-corp-phase3"
      team       = "TF3"
      mandate    = "12"
      managed-by = "terraform"
      purpose    = "organization-audit"
    }
  }
}

data "aws_caller_identity" "current" {}

