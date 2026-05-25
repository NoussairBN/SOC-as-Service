terraform {
  backend "s3" {
    bucket         = "pfs-soc-tfstate-eaysjpih"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "pfs-soc-tfstate-lock"
    encrypt        = true
  }
}
