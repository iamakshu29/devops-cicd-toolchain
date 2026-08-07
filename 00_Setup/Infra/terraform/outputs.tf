output "master_public_ip" {
  description = "Public IP of the Jenkins Master. Use this to SSH in: ssh -i jenkins_master.pem ubuntu@<ip>"
  value       = aws_instance.jenkins["jenkins_master"].public_ip
}

output "jenkins_url" {
  description = "Jenkins web UI"
  value       = "http://${aws_instance.jenkins["jenkins_master"].public_ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube web UI — default credentials: admin / admin"
  value       = "http://${aws_instance.jenkins["jenkins_master"].public_ip}:9000"
}

output "nexus_url" {
  description = "Nexus web UI — get initial password: docker exec nexus cat /nexus-data/admin.password"
  value       = "http://${aws_instance.jenkins["jenkins_master"].public_ip}:8081"
}

output "nexus_docker_registry" {
  description = "Nexus Docker hosted repository — use this as registry URL in Jenkins and daemon.json"
  value       = "${aws_instance.jenkins["jenkins_master"].public_ip}:8082"
}

output "instance_ids" {
  description = "EC2 instance IDs for all nodes"
  value = {
    for name, instance in aws_instance.jenkins : name => instance.id
  }
}
