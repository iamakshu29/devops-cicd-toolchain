ssh_key = {
  jenkins_master = {
    key_path = "jenkins_master.pub"
  }
}

instance = {
  jenkins_master = {
    size              = 50
    availability_zone = "us-east-1a"
    instance_type     = "t3a.large"
  }
  # jenkins_slave = {
  #   size              = 50
  #   availability_zone = "us-east-1c"
  #   instance_type     = "t3a.large"
  # }
}

security_group = {
  jenkins_master = {
    ingress = [
      {
        cidr_ipv4   = "0.0.0.0/0"
        from_port   = 22
        ip_protocol = "tcp"
        to_port     = 22
      },
      {
        cidr_ipv4   = "0.0.0.0/0"
        from_port   = 8080
        ip_protocol = "tcp"
        to_port     = 8080
      },
      {
        cidr_ipv4   = "0.0.0.0/0"
        from_port   = 9000
        ip_protocol = "tcp"
        to_port     = 9000
      },
      {
        cidr_ipv4   = "0.0.0.0/0"
        from_port   = 8081
        ip_protocol = "tcp"
        to_port     = 8082  # covers both Nexus UI (8081) and Nexus Docker repo (8082)
      }
    ]

    eggress = {
      cidr_ipv4   = "0.0.0.0/0"
      ip_protocol = "-1"
    }
  }

  # jenkins_slave = {
  #   ingress = [
  #     {
  #       from_port   = 22
  #       ip_protocol = "tcp"
  #       to_port     = 22
  #     }
  #   ]

  #   eggress = {
  #     cidr_ipv4   = "0.0.0.0/0"
  #     ip_protocol = "-1"
  #   }
  # }
}

ssm_parameter = {
  name        = "/jenkins/jenkins_slave/key"
  description = "It contains the private ssh key for jenkins slave node"
  type        = "SecureString"
}
