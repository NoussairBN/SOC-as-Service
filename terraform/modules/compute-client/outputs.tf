output "bastion_public_ip"          { value = aws_eip.bastion.public_ip }
output "bastion_instance_id"        { value = aws_instance.bastion.id }
output "dvwa_private_ip"            { value = aws_instance.dvwa.private_ip }
output "dvwa_instance_id"           { value = aws_instance.dvwa.id }
output "metasploitable_private_ip"  { value = aws_instance.metasploitable.private_ip }
output "metasploitable_instance_id" { value = aws_instance.metasploitable.id }
output "key_pair_name"              { value = aws_key_pair.pfs_soc.key_name }
