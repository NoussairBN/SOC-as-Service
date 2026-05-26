variable "project_name"        { type = string }
variable "environment"          { type = string }
variable "ami_id"               { type = string }
variable "instance_type_soc"    { type = string }
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
variable "soc_public_subnet_id" { type = string }
variable "sg_wazuh_id"          { type = string }
variable "key_pair_name" {
  type    = string
  default = ""
}
