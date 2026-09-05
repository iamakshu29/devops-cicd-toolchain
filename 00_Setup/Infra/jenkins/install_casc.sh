#!/bin/bash

set -euo pipefail

JENKINS_CASC_DIR=/var/lib/jenkins/casc_configs
JENKINS_CONFIG_DIR=/etc/jenkins
JENKINS_PLUGIN_DIR=/var/lib/jenkins/plugins
JENKINS_PLUGIN_MANAGER_DIR=/opt/jenkins-plugin-manager
JENKINS_PLUGIN_MANAGER_JAR="$JENKINS_PLUGIN_MANAGER_DIR/jenkins-plugin-manager.jar"

get_plugin_command() {
    if command -v jenkins-plugin-cli >/dev/null 2>&1; then
        PLUGIN_COMMAND=(jenkins-plugin-cli)
        return
    fi

    echo "jenkins-plugin-cli not found; downloading the Jenkins plugin manager"
    plugin_manager_version=$(curl --fail --silent --show-error --location \
        --retry 5 --retry-all-errors --retry-delay 5 \
        https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest \
        | grep '"tag_name"' | head -n 1 | cut -d '"' -f 4)

    sudo install -d -m 0755 "$JENKINS_PLUGIN_MANAGER_DIR"
    sudo curl --fail --silent --show-error --location \
        --retry 5 --retry-all-errors --retry-delay 5 \
        "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${plugin_manager_version}/jenkins-plugin-manager-${plugin_manager_version#v}.jar" \
        -o "$JENKINS_PLUGIN_MANAGER_JAR"
    PLUGIN_COMMAND=(java -jar "$JENKINS_PLUGIN_MANAGER_JAR")
}

install_plugins() {
    echo "Installing Jenkins plugins from $JENKINS_CONFIG_DIR/plugins.txt"
    for attempt in 1 2 3 4 5; do
        if sudo "${PLUGIN_COMMAND[@]}" \
            --war /usr/share/java/jenkins.war \
            --plugin-download-directory "$JENKINS_PLUGIN_DIR" \
            --plugin-file "$JENKINS_CONFIG_DIR/plugins.txt" \
            --verbose; then
            return 0
        fi
        echo "Plugin installation attempt ${attempt} failed; retrying" >&2
        sleep 10
    done

    echo "Jenkins plugin installation failed after 5 attempts" >&2
    return 1
}

sudo systemctl stop jenkins || true
sudo mkdir -p "$JENKINS_CASC_DIR" "$JENKINS_CONFIG_DIR"
sudo cp /tmp/jenkins-config/casc/jenkins.yml "$JENKINS_CASC_DIR/jenkins.yml"
sudo cp /tmp/jenkins-config/plugins.txt "$JENKINS_CONFIG_DIR/plugins.txt"
sudo chown -R jenkins:jenkins "$JENKINS_CASC_DIR"
sudo chmod 600 "$JENKINS_CASC_DIR/jenkins.yml"

sudo mkdir -p "$JENKINS_PLUGIN_DIR"
get_plugin_command
install_plugins

sudo mkdir -p /etc/systemd/system/jenkins.service.d
sudo tee /etc/systemd/system/jenkins.service.d/casc.conf >/dev/null <<'EOF'
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yml"
EnvironmentFile=/etc/jenkins/jenkins-secrets.env
EOF

sudo systemctl daemon-reload