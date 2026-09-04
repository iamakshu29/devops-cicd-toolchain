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

set -Eeuo pipefail

trap 'status=$?; echo "ERROR: command failed with status ${status} at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

download_file() {
    local url=$1
    local destination=$2

    echo "Downloading ${url}"
    curl --fail --silent --show-error --location \
        --retry 5 --retry-all-errors --retry-delay 5 \
        "$url" -o "$destination"
}

install_base_packages() {
    echo "=========================================================================================================================================="
    echo "Updating apt package"
    sudo apt update -y
    # wget and curl are required by install_trivy and install_cosign
    sudo apt install -y wget curl unzip

    # SonarQube + Elasticsearch requirement â€” persisted in AMI so all instances inherit it
    echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
    echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.max_map_count=524288
    sudo sysctl -w fs.file-max=131072
}


install_git() {
    echo "=========================================================================================================================================="
    echo "Checking for Git"
    if command -v git >/dev/null 2>&1; then
        echo "Git Already Present"
    else
        echo "Git not present, Installing Git"
        sudo apt install -y git
    fi
}


install_aws_cli() {
    echo "=========================================================================================================================================="
    echo "Checking for AWS CLI"
    if command -v aws >/dev/null 2>&1; then
        echo "AWS CLI Already Present"
    else
        echo "AWS CLI not present, Installing AWS CLI"
        download_file \
            "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
            "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
    fi
}

install_docker_and_docker_compose() {
    echo "=========================================================================================================================================="
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
            runc 2>/dev/null | awk '{print $1}' || true)

        if [ -n "$conflicting_packages" ]; then
            sudo apt remove -y $conflicting_packages
        fi

        sudo apt update -y
        sudo apt install -y ca-certificates curl

        sudo install -m 0755 -d /etc/apt/keyrings

        sudo curl --fail --silent --show-error --location \
            --retry 5 --retry-all-errors --retry-delay 5 \
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

    echo "------------------------------------------------------------------------------------------------------------------------------"
    echo "Docker version"
    sudo docker version

    echo "------------------------------------------------------------------------------------------------------------------------------"
    echo "Docker Compose version"
    sudo docker compose version
}


install_jdk21() {
    echo "=========================================================================================================================================="
    echo "Checking for JDK 21"
    if java -version 2>&1 | grep -q '"21'; then
        echo "JDK 21 Already Present"
    else
        echo "JDK 21 not present, Installing Eclipse Temurin JDK 21"
        curl --fail --silent --show-error --location \
            --retry 5 --retry-all-errors --retry-delay 5 \
            https://packages.adoptium.net/artifactory/api/gpg/key/public \
            | sudo gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
        echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] \
            https://packages.adoptium.net/artifactory/deb \
            $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
            | sudo tee /etc/apt/sources.list.d/adoptium.list
        sudo apt update -y
        sudo apt install -y temurin-21-jdk
    fi

    echo "------------------------------------------------------------------------------------------------------------------------------"
    java -version
    javac -version
}


install_jenkins_service() {
    echo "=========================================================================================================================================="
    echo "Checking for Jenkins"
    if command -v jenkins >/dev/null 2>&1; then
        echo "Jenkins Already Present"
    else
        echo "Jenkins not present, Installing Jenkins as a host systemd service"
        sudo curl --fail --silent --show-error --location \
            --retry 5 --retry-all-errors --retry-delay 5 \
            https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
            -o /usr/share/keyrings/jenkins-keyring.asc
        echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
            https://pkg.jenkins.io/debian-stable binary/" \
            | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
        sudo apt update -y
        sudo apt install -y jenkins
        sudo systemctl enable jenkins
    fi

    # Pipeline docker stages need the jenkins user in the docker group to run docker commands without sudo
    sudo usermod -aG docker jenkins

    # Shared trivy DB cache across all pipeline runs â€” jenkins user needs write access
    sudo mkdir -p /var/cache/trivy
    sudo chown jenkins:jenkins /var/cache/trivy
}


install_trivy(){
    echo "=========================================================================================================================================="
    echo "Checking for Trivy"
    if trivy --version >/dev/null 2>&1; then
        echo "Trivy is Present"
    else
        echo "---------------------------------------------------------------------------------------------------------------------------------"
        echo "Installing Trivy"
        TRIVY_VERSION=$(curl --fail --silent --show-error --location \
            --retry 5 --retry-all-errors --retry-delay 5 \
            https://api.github.com/repos/aquasecurity/trivy/releases/latest \
            | grep '"tag_name"' | cut -d '"' -f 4 | sed 's/^v//')
        if [ -z "$TRIVY_VERSION" ]; then
            echo "Unable to determine the latest Trivy version" >&2
            exit 1
        fi
        download_file \
            "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb" \
            /tmp/trivy.deb
        sudo dpkg -i /tmp/trivy.deb
        rm /tmp/trivy.deb
    fi
}


install_checkov() {
    echo "=========================================================================================================================================="
    echo "Checking for Checkov"
    if command -v checkov >/dev/null 2>&1; then
        echo "Checkov is Present"
    else
        echo "---------------------------------------------------------------------------------------------------------------------------------"
        echo "Installing Checkov"
        sudo apt install -y python3 python3-venv
        sudo python3 -m venv /opt/checkov
        sudo /opt/checkov/bin/pip install --upgrade pip
        sudo /opt/checkov/bin/pip install checkov
        sudo ln -sf /opt/checkov/bin/checkov /usr/local/bin/checkov
    fi
}

install_cosign() {
    echo "=========================================================================================================================================="
    echo "Checking for Cosign"
    if command -v cosign >/dev/null 2>&1; then
        echo "Cosign is Present"
    else
        echo "---------------------------------------------------------------------------------------------------------------------------------"
        echo "Installing Cosign"
        COSIGN_VERSION=$(curl --fail --silent --show-error --location \
            --retry 5 --retry-all-errors --retry-delay 5 \
            https://api.github.com/repos/sigstore/cosign/releases/latest \
            | grep '"tag_name"' | cut -d '"' -f 4)
        if [ -z "$COSIGN_VERSION" ]; then
            echo "Unable to determine the latest Cosign version" >&2
            exit 1
        fi
        curl --fail --silent --show-error --location \
            --retry 5 --retry-all-errors --retry-delay 5 \
            -o /tmp/cosign \
            "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
        chmod +x /tmp/cosign
        sudo mv /tmp/cosign /usr/local/bin/cosign
    fi

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Cosign version"
    cosign version
}

verify_installations() {
    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Git version"
    git --version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Java version"
    java -version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Javac version"
    javac -version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "AWS CLI version"
    aws --version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Docker version"
    sudo docker version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Docker Compose version"
    docker compose version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Trivy version"
    trivy --version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Checkov version"
    checkov --version

    echo "---------------------------------------------------------------------------------------------------------------------------------"
    echo "Cosign version"
    cosign version
}


install_base_packages
install_git
install_aws_cli
install_docker_and_docker_compose
install_jdk21
install_jenkins_service
install_trivy
install_checkov
install_cosign
verify_installations