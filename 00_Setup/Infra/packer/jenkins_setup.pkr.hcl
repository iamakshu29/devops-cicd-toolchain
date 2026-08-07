packer {
  required_plugins {
    amazon = {
      version = >= 1.2.8
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "ami_prefix" {
  type    = string
  default = "jenkins_master_ami"
}


source "amazon-ebs" "ubuntu" {
  ami_name      = "${var.ami_prefix}"
  instance_type = "t3a.large"
  region        = "us-east-1"
  source_ami_filter {
    most_recent = true

    owners = ["099720109477"] # Canonical

    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      virtualization-type = "hvm"
    }
  }
  ssh_username = "ubuntu"
}

build {
  name = "configure-jenkins"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
    script = "${path.root}/install_tools.sh"
  }

   post-processor "manifest" {
    output = "manifest.json"
  }
}
