# Ansible Automation Lab on AWS

## Objective

Build a fully automated Ansible lab that can be recreated from scratch using Infrastructure as Code.

The project demonstrates:

* Packer
* Terraform
* Create SSH key pair using command -> ssh-keygen -t rsa -b 4096 -f ansible_managed_node -N ""
* AWS EC2
* Ansible
* Dynamic Inventory

The goal is to provision infrastructure, configure servers using Ansible, and destroy the infrastructure when finished to minimize AWS costs.

---

# Architecture

```text
          ansible_nodes_setup.sh
                    │
       ┌────────────┴────────────┐
       │                         │
       ▼                         ▼
  Packer Build              Terraform Apply
  (One Time)                     │
       │               ┌─────────┴─────────┐
       ▼               │                   │
  Controller AMI  1 Controller EC2     2 Managed Node EC2s
                        │
                        ▼
               Clone GitHub Repo + Run Ansible Playbooks
                        │
                        ▼
         AWS EC2 Dynamic Inventory
         (discovers managed nodes by tag)
                        │
                        ▼
             Configure Managed Nodes
```

---

# Project Structure

```text
Ansible/
│
├── Infra/
│   ├── ansible_nodes_setup.sh     ← single entry point (apply / destroy)
│   ├── manifest.json              ← packer AMI output
│   ├── packer/
│   │   ├── ansible_controller_node.pkr.hcl
│   │   └── install_tools.sh
│   └── terraform/
│       ├── ec2.tf                 ← provisions controller + managed nodes
│       ├── sg.tf
│       ├── role_and_policy.tf
│       └── variables.tf
│
└── <module folders>/
    ├── playbooks
    ├── inventory/
    └── roles/
```

---

# Roadmap

## Phase 1 – Infrastructure Provisioning ✅ (Automated)

Handled entirely by `ansible_nodes_setup.sh`.

**apply:**
1. Checks AWS CLI, Packer, Terraform are available
2. Builds controller AMI with Packer (skipped if AMI already exists in `manifest.json`)
3. Provisions controller EC2 + managed node EC2s with Terraform in a single apply

**destroy:**
```bash
./ansible_nodes_setup.sh destroy            # keeps AMI
./ansible_nodes_setup.sh destroy --delete-ami  # also deregisters AMI + snapshots
```

AMI includes: Ansible, AWS CLI, Git, required collections.

---

## Phase 2 – Dynamic Inventory

Configure the AWS EC2 Inventory Plugin on the controller.

Inventory automatically discovers EC2 instances using tags set during Terraform provisioning.

Example tags:

```
Environment = Lab
Role = Worker
```

No static inventory file should be maintained for managed nodes.

---

# Future Enhancements

* Optional Infrastructure Cleanup
* Terraform Remote State (S3 + DynamoDB)
* Molecule Testing
* Versioned Packer Images
* Automatic AMI Discovery in Terraform

---

# Learning Order

Build the project in this sequence:

* [x] Write Packer template (controller AMI)
* [x] Write Terraform (controller + managed nodes)
* [x] Write `ansible_nodes_setup.sh` (single entry point)
* [x] Configure IAM Role + Security Groups
* [ ] Configure AWS EC2 Dynamic Inventory
* [ ] Write and execute Ansible Playbooks
* [ ] Destroy infrastructure when done

---

# End-to-End Workflow

```
./ansible_nodes_setup.sh apply
        │
        ▼
Packer builds Controller AMI (once)
        │
        ▼
Terraform provisions Controller + Managed Nodes
        │
        ▼
SSH into Controller, clone repo, run Ansible Playbooks
        │
        ▼
Dynamic Inventory discovers Managed Nodes by tag
        │
        ▼
Managed Nodes configured
        │
        ▼
./ansible_nodes_setup.sh destroy (--delete-ami)
```

---

# Skills Demonstrated

* Infrastructure as Code (Terraform)
* Image Baking (Packer)
* Configuration Management (Ansible)
* AWS EC2
* IAM Roles
* Dynamic Inventory
* Infrastructure Lifecycle Management