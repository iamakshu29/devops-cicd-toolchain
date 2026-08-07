resource "aws_security_group" "jenkins_sg" {
  for_each    = var.security_group
  name        = "${each.key}-sg"
  description = "Allow SSH inbound traffic and all outbound traffic"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = each.key
  }
}

# Flatten each SG's ingress rule list into individual keyed entries for for_each
resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4_jenkins_server_rule" {
  for_each = { for rule in local.ingress_rules : "${rule.sg_name}_${rule.idx}" => rule }

  security_group_id            = aws_security_group.jenkins_sg[each.value.sg_name].id
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.sg_name == "jenkins_slave" ? aws_security_group.jenkins_sg["jenkins_master"].id : null
  from_port                    = each.value.from_port
  ip_protocol                  = each.value.ip_protocol
  to_port                      = each.value.to_port
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_jenkins_server_rule" {
  for_each = var.security_group

  security_group_id = aws_security_group.jenkins_sg[each.key].id
  cidr_ipv4         = each.value.eggress.cidr_ipv4
  ip_protocol       = each.value.eggress.ip_protocol
}
