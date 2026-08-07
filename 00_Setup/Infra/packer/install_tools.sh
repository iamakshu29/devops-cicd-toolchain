#!/bin/bash

###############################################################################
# Script Name : install_tools.sh
# Description : Install pre-requisites required for the Pipeline Tutorial
# Version     : 1.0.0
# Author      : Akshat Verma
# Created     : 2026-07-10
# Last Updated: 2026-07-10
# License     : MIT
# Usage       : 
# Requirements: 
###############################################################################

set -euo pipefail

install_base_packages() {
    echo "====================================================================="
    echo "Updating apt package"
    sudo apt update -y
}


install_git() {
    echo "====================================================================="
    echo "Checking for Git"
    if command -v git >/dev/null 2>&1; then
        echo "Git Already Present"
    else
        echo "Git not present, Installing Git"
        sudo apt install -y git 
    fi
}


install_aws_cli() {
    echo "====================================================================="
    echo "Checking for AWS CLI"
    if command -v aws >/dev/null 2>&1; then
        echo "AWS CLI Already Present"
    else
        echo "AWS CLI not present, Installing AWS CLI"
        sudo apt install -y awscli
    fi
}

install_docker_and_docker_compose() {
    echo "====================================================================="
    echo "Checking for Docker"

    if command -v docker >/dev/null 2>&1; then
        echo "Docker Already Present"
    else
        echo "Docker not present, Installing Docker"

        conflicting_packages=$(dpkg --get-selections \
            docker.io \
            docker-compose \
            docker-compose-v2 \
            docker-doc \
            docker-buildx \
            podman-docker \
            containerd \
            runc 2>/dev/null | awk '{print $1}')

        if [ -n "$conflicting_packages" ]; then
            sudo apt remove -y $conflicting_packages
        fi

        sudo apt update -y
        sudo apt install -y ca-certificates curl

        sudo install -m 0755 -d /etc/apt/keyrings

        sudo curl -fsSL \
            https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        sudo chmod a+r /etc/apt/keyrings/docker.asc

        sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

        sudo apt update -y

        sudo apt install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        sudo systemctl enable docker
        sudo systemctl start docker

        sudo groupadd -f docker
        sudo usermod -aG docker "$USER"
    fi

    echo "---------------------------------------------------------------"
    echo "Docker version"
    sudo docker version

    echo "---------------------------------------------------------------"
    echo "Docker Compose version"
    sudo docker compose version
}


install_jenkins(){
    echo "====================================================================="
    echo "Checking for Jenkins"
    if docker container inspect jenkins >/dev/null 2>&1; then
        echo "---------------------------------------------------------------"
        echo "Jenkins Already Present"
        echo "Check if Jenkins is running"

        if docker container inspect -f '{{.State.Running}}' jenkins 2>/dev/null | grep -q true; then
            echo "---------------------------------------------------------------"
            echo "Jenkins is Running"
        else
            echo "Jenkins exists but is not running"
            docker start jenkins
        fi

    else

        echo "Image not present, Building One"
        docker pull jenkins/jenkins:lts-jdk21

        echo "---------------------------------------------------------------"
        echo "Creating Volume to persist data"
        docker volume create jenkins_home

        echo "---------------------------------------------------------------"
        echo "Starting the Jenkins Container"
        docker run -d --name jenkins --restart unless-stopped -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts-jdk21
    fi
}


install_trivy(){
    echo "====================================================================="
    echo "Checking for Trivy"
    if trivy --version >/dev/null 2>&1; then
        echo "Trivy is Present"
    else
        echo "---------------------------------------------------------------"
        echo "Installing Trivy"
        wget https://github.com/aquasecurity/trivy/releases/download/v0.73.0/trivy_0.73.0_Linux-64bit.deb
        sudo dpkg -i trivy_0.73.0_Linux-64bit.deb   
    fi
}


install_checkov() {
    echo "====================================================================="
    echo "Checking for Checkov"
    if command -v checkov >/dev/null 2>&1; then
        echo "Checkov is Present"
    else
        echo "---------------------------------------------------------------"
        echo "Installing Checkov"
        sudo apt install -y python3 python3-venv
        sudo python3 -m venv /opt/checkov
        sudo /opt/checkov/bin/pip install --upgrade pip
        sudo /opt/checkov/bin/pip install checkov
        sudo ln -sf /opt/checkov/bin/checkov /usr/local/bin/checkov
    fi
}

install_cosign() {
    echo "====================================================================="
    echo "Checking for Cosign"
}

verify_installations() {
    echo "---------------------------------------------------------------"
    echo "Git version"
    git --version

    echo "---------------------------------------------------------------"
    echo "AWS CLI version"
    aws --version

    echo "---------------------------------------------------------------"
    echo "Docker version"
    sudo docker version

    echo "---------------------------------------------------------------"
    echo "Docker Compose version"
    docker compose version

    echo "---------------------------------------------------------------"
    echo "Trivy version"
    trivy --version

    echo "---------------------------------------------------------------"
    echo "Checkov version"
    checkov --version
}


install_base_packages
install_git
install_aws_cli
install_docker_and_docker_compose
install_jenkins
install_trivy
install_checkov
install_cosign
verify_installations

echo "Get urls for jenkins, nexus, sonarqube and if there any other required"