resource "aws_ssm_parameter" "store_jenkins_master_key" {
  name        = var.ssm_parameter.name
  description = var.ssm_parameter.description
  type        = var.ssm_parameter.type
  value       = tls_private_key.jenkins_master.private_key_pem
}
