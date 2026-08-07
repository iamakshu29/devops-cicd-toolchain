resource "aws_key_pair" "jenkins_key" {
  for_each   = var.ssh_key
  key_name   = each.key
  public_key = file("${path.module}/${each.value.key_path}")
}

resource "aws_key_pair" "jenkins_slave" {
  key_name   = "jenkins_slave"
  public_key = tls_private_key.jenkins_slave.public_key_openssh
}

resource "aws_instance" "jenkins" {
  for_each = var.instance

  ami                    = each.key == "jenkins_master" ? var.jenkins_master_ami_id : data.aws_ami.ubuntu.id
  instance_type          = each.value.instance_type
  key_name               = each.key == "jenkins_master" ? aws_key_pair.jenkins_key["jenkins_master"].key_name : aws_key_pair.jenkins_slave.key_name
  subnet_id              = data.aws_subnet.default[each.value.availability_zone].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg[each.key].id]
  iam_instance_profile   = each.key == "jenkins_master" ? aws_iam_instance_profile.jenkins_master.name : null

  user_data = each.key == "jenkins_master" ? file("${path.module}/user_data.sh") : null

  root_block_device {
    volume_size = each.value.size
    encrypted   = true
  }

  tags = each.key == "jenkins_master" ? {
    Name        = each.key
    Role        = "master"
    Environment = "lab"
    } : {
    Name        = each.key
    Role        = "slave"
    Environment = "lab"
  }

  depends_on = [aws_ssm_parameter.store_jenkins_slave_key]
}
