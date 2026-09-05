#!/bin/bash

set -euo pipefail

echo "Create the env file"
sudo touch /etc/Jenkins/jenkins-secrets.env

echo "Add the ENVs"
sudo tee /etc/jenkins/jenkins-secrets.env > /dev/null <<EOF
JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD}
JENKINS_USER1_PASSWORD=${JENKINS_USER1_PASSWORD}
JENKINS_URL=${JENKINS_URL}
SONARQUBE_TOKEN=${SONARQUBE_TOKEN}
NVD_API_KEY=${NVD_API_KEY}
DOCKERHUB_USERNAME=${DOCKERHUB_USERNAME}
DOCKERHUB_TOKEN=${DOCKERHUB_TOKEN}
COSIGN_PRIVATE_KEY=${COSIGN_PRIVATE_KEY}
COSIGN_KEY_PASSWORD=${COSIGN_KEY_PASSWORD}
EOF

echo "Secure the file by modifying users and permissions"
sudo chown root:root /etc/jenkins/jenkins-secrets.env
sudo chmod 600 /etc/jenkins/jenkins-secrets.env

echo "Reload Daemon, Start and Enable Jenkins, Checking the Status"
sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status Jenkins --no-pager
sudo journalctl -u Jenkins -f