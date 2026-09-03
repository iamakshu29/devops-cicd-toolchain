#!/bin/bash
# Runs at instance boot. Packer AMI already has Docker, Jenkins, Trivy, Checkov, Cosign.
# This script handles runtime-only setup: kernel settings and starting stateful tool containers.

set -euo pipefail

# Required for SonarQube + Elasticsearch — persist across reboots and apply immediately
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
sysctl -w vm.max_map_count=524288
sysctl -w fs.file-max=131072

# Jenkins requires the manually supplied secrets file before CasC can start it.
if [[ -f /etc/jenkins/jenkins-secrets.env ]]; then
  systemctl start jenkins
else
  echo "Jenkins is not started: /etc/jenkins/jenkins-secrets.env is missing."
fi

# Start SonarQube + Nexus via Docker Compose
mkdir -p /home/ubuntu/cicd
cat > /home/ubuntu/cicd/docker-compose.yml <<'EOF'
version: "3.8"
services:
  sonarqube:
    image: sonarqube:26.8.0.126808-community
    container_name: sonarqube
    depends_on: [sonar-db]
    ports:
      - "9000:9000"
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://sonar-db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar_pass
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_extensions:/opt/sonarqube/extensions

  sonar-db:
    image: postgres:15-alpine
    container_name: sonar-db
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar_pass
      POSTGRES_DB: sonar
    volumes:
      - sonar_pg_data:/var/lib/postgresql/data

  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    ports:
      - "8081:8081"
      - "8082:8082"
    volumes:
      - nexus_data:/nexus-data

volumes:
  sonarqube_data:
  sonarqube_logs:
  sonarqube_extensions:
  sonar_pg_data:
  nexus_data:
EOF

chown -R ubuntu:ubuntu /home/ubuntu/cicd
cd /home/ubuntu/cicd && docker compose up -d

