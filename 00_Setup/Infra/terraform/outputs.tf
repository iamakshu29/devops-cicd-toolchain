output "master_public_ip" {
  description = "Public IP of the Jenkins Master. Use this to SSH in: ssh -i jenkins_master.pem ubuntu@<ip>"
  value       = aws_instance.jenkins["jenkins_master"].public_ip
}

# output "slave_private_ips" {
#   description = "Private IPs of managed nodes (for reference — dynamic inventory discovers these automatically)"
#   value = {
#     for name, instance in aws_instance.ansible : name => instance.private_ip
#     if name != "jenkins_master"
#   }
# }

output "instance_ids" {
  description = "EC2 instance IDs for all nodes"
  value = {
    for name, instance in aws_instance.jenkins : name => instance.id
  }
}
