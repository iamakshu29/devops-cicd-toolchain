variable "ssh_key" {
  type = map(any)
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

variable "jenkins_master_ami_id" {
  description = "Custom AMI ID built by Packer with Docker + CI tools pre-installed. Get from packer/manifest.json after packer build."
  type        = string
  default     = ""  # leave empty to use latest Ubuntu (user_data.sh installs tools at boot instead)
}