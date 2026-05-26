variable "project_name"              { type = string }
variable "environment"               { type = string }
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_client_cidr"           { type = string }
variable "vpc_soc_cidr"              { type = string }
variable "client_public_subnet_cidr" { type = string }
variable "client_private_subnet_cidr"{ type = string }
variable "soc_public_subnet_cidr"    { type = string }
variable "my_public_ip"              { type = string }
