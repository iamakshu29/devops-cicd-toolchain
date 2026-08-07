resource "tls_private_key" "jenkins_master" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
