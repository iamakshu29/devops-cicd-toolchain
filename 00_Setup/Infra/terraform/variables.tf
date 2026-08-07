variable "ssh_key" {
  type = map(any)
}

variable "jenkins_master_ami_id" {
  description = "AMI ID for the Jenkins Master node"
  type        = string
}

variable "instance" {
  type = map(any)
}

variable "security_group" {
  type = map(any)
}

variable "ssm_parameter" {
  type = map(any)
}