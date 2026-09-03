# Ansible Automation Lab on AWS

## Objective

Build a fully automated Ansible lab that can be recreated from scratch using Infrastructure as Code.

The project demonstrates:

- Packer
- Terraform
- Create SSH key pair using command -> `ssh-keygen -t rsa -b 4096 -f jenkins_master -N ""`
- AWS EC2
- Jenkins with CI/CD Tools

The goal is to provision infrastructure, configure servers using Ansible, and destroy the infrastructure when finished to minimize AWS costs.

---

# Architecture

```text
          jenkins_nodes_setup.sh
                    │
       ┌────────────┴────────────┐
       │                         │
       ▼                         ▼
  Packer Build              Terraform Apply
  (One Time)                     │
       │               ┌─────────┴─────────┐
       ▼               │                   │
  jenkins_setup AMI  Master              Slave

```

---

# Project Structure

```text
devops-cicd-toolchain/
│
├── Infra/
│   ├── jenkins_nodes_setup.sh     ← single entry point (apply / destroy)
│   ├── manifest.json              ← packer AMI output
│   ├── packer/
│   │   ├── jenkins_setup.pkr.hcl
│   │   └── install_tools.sh
│   └── terraform/
│       ├── ec2.tf                 ← provisions master + slave ec2 (if required)
│       ├── sg.tf
│       ├── role_and_policy.tf
│       └── variables.tf
│
└── <module folders>/
    ├── Different Tools Folders
    ├── Full Pipeline Project
    └── Reference Project
```

---

# Roadmap

## Phase 1 – Infrastructure Provisioning ✅ (Automated)

Handled entirely by `jenkins_nodes_setup.sh`.

**apply:**

```bash
./jenkins_nodes_setup.sh apply
```

1. Checks AWS CLI, Packer, Terraform are available
2. Builds Master AMI with Packer (skipped if AMI already exists in `manifest.json`)
3. Provisions EC2s with Terraform in a single apply

**destroy:**

```bash
./jenkins_nodes_setup.sh destroy            # keeps AMI
./jenkins_nodes_setup.sh destroy --delete-ami  # also deregisters AMI + snapshots
```

---
