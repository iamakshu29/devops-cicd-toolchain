# Pipeline Environment Setup Guide

> **Different tools need different environments.**
> You do not need everything running before you start.
> This guide maps each tool to the right setup option and tells you exactly what to provision.

---

## Environment Options at a Glance

| Option | Cost | Best For | Persistent? | Setup Time |
|--------|------|----------|-------------|------------|
| **A — Local machine** | Free | Trivy, Checkov (no server needed) | Yes | 5 min |
| **B — AWS EC2 t3a.large** | ~$0.08/hr, stop when not practicing | Tools 01–09, full stack | Per session | 10 min once |
| **C — Oracle Free Tier** | Always free | Same as B, preferred if you want persistent | Yes (always on) | 30 min once |
| **Existing K8s cluster** | Already have it | Vault, Kyverno, Cosign (tools 06, 07, 08) | Yes | 0 min |

---

## Tool → Environment Mapping

| Tool | What It Needs | Use This |
|------|--------------|----------|
| 03 — Trivy | Just a binary | **Option A** — your laptop |
| 04 — Checkov | Just pip install | **Option A** — your laptop |
| 02 — OWASP DC | Jenkins + plugin | **Option B or C** |
| 01 — SonarQube | Server (Docker) + Jenkins | **Option B or C** |
| 05 — Nexus | Server (Docker) + Jenkins | **Option B or C** |
| 07 — Cosign | Binary + registry access | **Option B or C** (after Nexus is up) |
| 06 — Vault | K8s Helm install | **Existing K8s cluster** |
| 08 — Kyverno | K8s Helm install | **Existing K8s cluster** |
| 09 — Notifications | Slack webhook + Jenkins | **Option B or C** |
| 10 — Full Project | Everything | **Option B or C** + K8s cluster |

---

## Option A — Local Machine (Start Here — Tools 03 and 04)

Zero infrastructure. Do this today.

### Install Trivy (WSL or PowerShell)

```bash
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy
trivy --version
```

Or via Docker (no install at all):
```bash
docker run --rm aquasec/trivy image nginx:latest
```

First thing to run — compare finding counts across base images:
```bash
trivy image nginx:latest
trivy image ubuntu:22.04
trivy image alpine:3.19
```

### Install Checkov

```powershell
pip install checkov
checkov --version
```

Run on your own existing files immediately:
```bash
checkov -d "C:\Users\akshat.b.verma\OneDrive - Accenture\Desktop\My-Devops\Ansible\Infra\terraform"
checkov -d "C:\Users\akshat.b.verma\OneDrive - Accenture\Desktop\My-Devops\K8s" --framework kubernetes
```

---

## Option B — AWS EC2 (Recommended for Tools 01–09)

Single `t3a.large` instance running Docker Compose for Jenkins + SonarQube + Nexus.
Packer bakes a custom AMI with all CI tools pre-installed. `user_data.sh` starts SonarQube + Nexus at launch.

All Terraform and Packer files are in `Infra/terraform/` and `Infra/packer/`.
The setup is fully automated via `jenkins_nodes_setup.sh`.

---

### Step 1 — Generate SSH Key Pair

```bash
cd Pipeline/00_Setup/Infra/terraform/
ssh-keygen -t rsa -b 4096 -f jenkins_master -N ""
# jenkins_master     → private key (keep this, use it to SSH)
# jenkins_master.pub → already referenced in terraform.tfvars
```

---

### Step 2 — Run the Setup Script

```bash
cd Pipeline/00_Setup/Infra/
./jenkins_nodes_setup.sh apply
```

What the script does automatically:
1. Checks if a valid AMI already exists in `manifest.json` → **skips Packer rebuild** if AMI is still in AWS
2. If no AMI → runs `packer build` (~10 minutes) → saves AMI ID to `manifest.json`
3. Passes AMI ID to Terraform via `-var=` flag — no manual `terraform.tfvars` edit needed
4. Runs `terraform validate → plan → apply`

After apply:
```
master_public_ip = "x.x.x.x"
```
Wait 3–4 minutes for `user_data.sh` to start SonarQube + Nexus.

---

### Step 3 — Verify Everything is Running

```bash
ssh -i jenkins_master ubuntu@<master_public_ip>

docker ps | grep jenkins     # Running (started by Packer AMI)
docker ps | grep sonarqube   # Up (started by user_data.sh)
docker ps | grep nexus       # Up (started by user_data.sh)

trivy --version
checkov --version
cosign version
```

Access from browser:
```
http://<master_public_ip>:8080   → Jenkins    (password below)
http://<master_public_ip>:9000   → SonarQube  (admin / admin)
http://<master_public_ip>:8081   → Nexus      (password below)
```

Initial passwords:
```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
docker exec nexus cat /nexus-data/admin.password
```

---

### Step 4 — After Instance Stop/Start

```bash
ssh -i jenkins_master ubuntu@<new_public_ip>   # IP changes on every start

docker start jenkins
cd /home/ubuntu/cicd && docker compose up -d
```

---

### Cost Control

```bash
# Stop instance (no compute charge — ~$0.03/day storage only)
aws ec2 stop-instances --instance-ids <id>

# Destroy EC2 but keep the AMI (next apply skips Packer rebuild)
cd Pipeline/00_Setup/Infra/
./jenkins_nodes_setup.sh destroy

# Destroy EC2 AND delete AMI + EBS snapshots (clean slate)
./jenkins_nodes_setup.sh destroy --delete-ami
```

Next session: `./jenkins_nodes_setup.sh apply` — if the AMI still exists, only Terraform runs (~2 min).

---

## Option C — Oracle Free Tier (Preferred if You Want Always-On)

You already have Oracle Free Tier set up for K8s. Create a second VM for the CI/CD stack.

1. OCI Console → Compute → Instances → Create Instance
   - Shape: `VM.Standard.A1.Flex` (ARM — always free)
   - OCPUs: 2 | RAM: 12GB | OS: Ubuntu 22.04
   - Add your SSH key
2. Open ports in VCN Security List: `22, 8080, 8081, 8082, 9000`
3. SSH in and run `install_tools.sh` from `Infra/packer/`:
   ```bash
   bash install_tools.sh
   ```
4. Then start SonarQube + Nexus via the docker-compose in `user_data.sh`.

**Advantage over AWS:** Always running, no stop/start needed, no cost concern.

---

## K8s Cluster — For Tools 06, 07, 08 (Vault, Cosign, Kyverno)

Use your existing K8s cluster from the K8s exercises.

```bash
kubectl get nodes   # verify it is running

# Vault (tool 06)
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
helm install vault hashicorp/vault --namespace vault --create-namespace \
  --set "injector.enabled=true" --set "server.dev.enabled=true"

# Kyverno (tool 08)
helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace

# Cosign (tool 07) — binary already installed by install_tools.sh
```

---

## Recommended Start Sequence

```
Day 1:   Option A (local)   → trivy image nginx:latest
                            → checkov -d your-terraform-folder
         No provisioning needed. Start today.

Day 3:   Option B           → ./jenkins_nodes_setup.sh apply
                            → Begin 02_OWASP_Dependency_Check

Day 5+:  SonarQube          → 01_SonarQube (after OWASP DC, concepts are familiar)

Week 2:  Nexus              → 05_Nexus — Docker hosted repo, push first image

Week 3:  K8s cluster        → helm install vault + kyverno
                            → 06_Vault, 08_Kyverno, 07_Cosign
```

---

## Daily Workflow Cheatsheet

```bash
# Start your session (AWS)
aws ec2 start-instances --instance-ids <id>
ssh -i jenkins_master ubuntu@<ip>
docker start jenkins
cd /home/ubuntu/cicd && docker compose up -d

# End your session
docker compose stop                    # preserves data (volumes persist)
aws ec2 stop-instances --instance-ids <id>

# Full clean restart (wipes all SonarQube projects + Nexus repos)
docker compose down -v
docker compose up -d
```

---

## Port Reference

| Service | URL from Browser | URL from Inside Jenkins Container |
|---------|-----------------|----------------------------------|
| Jenkins | `http://<ip>:8080` | `http://jenkins:8080` |
| SonarQube | `http://<ip>:9000` | `http://sonarqube:9000` |
| Nexus UI | `http://<ip>:8081` | `http://nexus:8081` |
| Nexus Docker | `http://<ip>:8082` | `http://nexus:8082` |

**Important:** When configuring tool URLs inside Jenkins (SonarQube server URL, Nexus registry), always use the Docker container name, not the public IP or `localhost`. From inside a container, `localhost` refers to that container itself.