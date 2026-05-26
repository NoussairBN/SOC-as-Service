terraform {
  backend "s3" {
    bucket         = "pfs-soc-tfstate-eaysjpih"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}
