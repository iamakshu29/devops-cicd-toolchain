#!/bin/bash

set -euo pipefail

JENKINS_CASC_DIR=/var/lib/jenkins/casc_configs
JENKINS_CONFIG_DIR=/etc/jenkins

sudo systemctl stop jenkins || true
sudo mkdir -p "$JENKINS_CASC_DIR" "$JENKINS_CONFIG_DIR"
sudo cp /tmp/jenkins-config/casc/jenkins.yml "$JENKINS_CASC_DIR/jenkins.yml"
sudo cp /tmp/jenkins-config/plugins.txt "$JENKINS_CONFIG_DIR/plugins.txt"
sudo chown -R jenkins:jenkins "$JENKINS_CASC_DIR"
sudo chmod 600 "$JENKINS_CASC_DIR/jenkins.yml"

if command -v jenkins-plugin-cli >/dev/null 2>&1; then
    echo "Installing Jenkins plugins from $JENKINS_CONFIG_DIR/plugins.txt"
    plugin_install_succeeded=false
    for attempt in 1 2 3 4 5; do
        if sudo jenkins-plugin-cli \
            --plugin-file "$JENKINS_CONFIG_DIR/plugins.txt" \
            --verbose; then
            plugin_install_succeeded=true
            break
        fi
        echo "Jenkins plugin installation attempt ${attempt} failed; retrying" >&2
        sleep 10
    done
    if [ "$plugin_install_succeeded" != true ]; then
        echo "Jenkins plugin installation failed after 5 attempts" >&2
        exit 1
    fi
else
    echo "jenkins-plugin-cli is not available"
    echo "Install Jenkins successfully before running install_casc.sh" >&2
    exit 1
fi

sudo mkdir -p /etc/systemd/system/jenkins.service.d
sudo tee /etc/systemd/system/jenkins.service.d/casc.conf >/dev/null <<'EOF'
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yml"
EnvironmentFile=/etc/jenkins/jenkins-secrets.env
EOF

sudo systemctl daemon-reload