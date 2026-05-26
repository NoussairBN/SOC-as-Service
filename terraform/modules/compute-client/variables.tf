variable "project_name"        { type = string }
variable "environment"          { type = string }
variable "ami_id"               { type = string }
variable "instance_type_micro"  { type = string }
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
variable "public_subnet_id"     { type = string }
variable "private_subnet_id"    { type = string }
variable "sg_bastion_id"        { type = string }
variable "sg_client_private_id" { type = string }
