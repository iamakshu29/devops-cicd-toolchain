#!/bin/bash

set -euo pipefail

ENV_FILE="./jenkins.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

echo "Create the env file"

sudo touch /etc/jenkins/jenkins-secrets.env

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

sudo chown root:root /etc/jenkins/jenkins-secrets.env
sudo chmod 600 /etc/jenkins/jenkins-secrets.env

sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins

sudo systemctl status jenkins --no-pager
sudo journalctl -u jenkins -f