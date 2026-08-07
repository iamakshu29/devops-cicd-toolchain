resource "aws_ssm_parameter" "store_jenkins_slave_key" {
  name        = var.ssm_parameter.name
  description = var.ssm_parameter.description
  type        = var.ssm_parameter.type
  value       = tls_private_key.jenkins_slave.private_key_pem
}
