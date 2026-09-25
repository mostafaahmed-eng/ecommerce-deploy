terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Intentionally NO backend block: this profile is applied from a trusted
  # workstation / CI job with local state by default. Add a remote backend here
  # if you want the demo state stored in S3 as well.
}
