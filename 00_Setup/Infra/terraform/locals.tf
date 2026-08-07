locals {
  instance_sg_map = {
    jenkins_master = "jenkins_master"
    # jenkins_slave  = "jenkins_slave"
  }

  ingress_rules = flatten([
    for sg_name, sg_config in var.security_group : [
      for idx, rule in sg_config.ingress : {
        sg_name     = sg_name
        idx         = idx
        cidr_ipv4   = lookup(rule, "cidr_ipv4", null)
        from_port   = rule.from_port
        ip_protocol = rule.ip_protocol
        to_port     = rule.to_port
      }
    ]
  ])
}
