resource "tls_private_key" "jenkins_slave" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
