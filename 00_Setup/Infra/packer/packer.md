# Packer Notes

## Is Packer idempotent?

No.

Unlike Terraform or Ansible, Packer does not compare the current state with the desired state. Every `packer build` starts a temporary instance, provisions it, creates a new machine image, and terminates the temporary instance.

* Terraform → State management (idempotent)
* Ansible → Configuration management (idempotent when playbooks are written correctly)
* Packer → Image creation (not idempotent)

---

## AMI Naming

Using a fixed AMI name such as:

```hcl
ami_name = "jenkins_master_ami"
```

works only for the first build.

Running Packer again in the same AWS account and region results in a duplicate AMI name error because AWS requires AMI names to be unique.

Common production practice is to use versioned names, for example:

* jenkins-master-20260710-101530
* jenkins-master-v1.2.0
* jenkins-master-a4f2c1d (Git commit SHA)

---

## Terraform Destroy

`terraform destroy` removes only the resources managed by Terraform.

It does **not** remove the AMI created by Packer because Terraform typically reads it through a data source rather than managing it as a resource.

Therefore:

* EC2 instances → Destroyed
* Security Groups → Destroyed
* IAM resources → Destroyed (if managed by Terraform)
* Packer AMI → Remains
* EBS snapshot backing the AMI → Remains

---

## Development / Lab Workflow

A practical workflow for this project is:

1. Build the AMI with Packer — `install_tools.sh` runs as the shell provisioner and installs JDK 21, Jenkins (systemd service), Docker, Trivy, Checkov, and Cosign directly on the image.
2. Deploy infrastructure with Terraform — EC2 launches from the AMI, `user_data.sh` starts SonarQube and Nexus via Docker Compose, and starts the Jenkins service.
3. Access Jenkins at `http://<ec2-public-ip>:8080` — all tools are already on the host, no further configuration step needed.
4. Destroy infrastructure when finished.
5. Optionally clean up the AMI and snapshot to avoid accumulating resources.

Another option is to check whether the AMI already exists before running Packer. If it exists and the image hasn't changed, skip the build. The `jenkins_nodes_setup.sh` script already does this by checking `manifest.json`.

---

## Production Workflow

In production, AMIs are treated as immutable, versioned artifacts.

Typical flow:

Git → Jenkins → Packer → Versioned AMI → Terraform → Deployment

The AMI is **not** deleted after deployment because it enables:

* Rollback to previous versions
* Reproducible deployments
* Auditability
* Consistent infrastructure across environments

Old AMIs are removed later by a separate cleanup job or retention policy (for example, keep the latest 10 images or all images from the last 30 days).

---

## Best Practices

* Build immutable images.
* Use versioned AMI names instead of fixed names.
* Deploy specific AMI versions with Terraform.
* Avoid rebuilding identical images unless the image inputs have changed.
* Keep AMIs for rollback and disaster recovery.
* Use a scheduled cleanup process rather than deleting AMIs immediately after deployment.
