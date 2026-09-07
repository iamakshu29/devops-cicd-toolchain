# Setup Flow

1. Create infra

   ```bash
   cd 00_Setup/Infra
   sh jenkins_nodes_setup.sh apply
   ```

2. Create cosign key (one time)

   ```bash
   cosign generate-key-pair
   base64 -w0 cosign.key
   ```

3. Put all values in `jenkins/env_setup/jenkins.env`
   (jenkins IP, base64 cosign key, github, dockerhub, sonar, nvd)

4. Copy `jenkins.yml` to the server (needed whenever you edit it, since it is baked in the AMI)

   ```bash
   cd 00_Setup/Infra/terraform
   IP=<jenkins_public_ip>
   scp -i jenkins_master ../jenkins/casc/jenkins.yml ubuntu@$IP:/tmp/jenkins.yml
   ssh -i jenkins_master ubuntu@$IP '
     sudo cp /tmp/jenkins.yml /var/lib/jenkins/casc_configs/jenkins.yml
     sudo chown jenkins:jenkins /var/lib/jenkins/casc_configs/jenkins.yml
     sudo chmod 600 /var/lib/jenkins/casc_configs/jenkins.yml'
   ```

5. Copy env script and run it

   ```bash
   scp -i jenkins_master -r ../jenkins/env_setup/ ubuntu@$IP:/tmp/
   ssh -i jenkins_master ubuntu@$IP 'cd /tmp/env_setup && sh env_setup.sh'
   ```

6. In Jenkins

   - Add OWASP Dependency-Check tool manually (not in CasC)
   - Copy the pipeline and run it

---

Notes

- `jenkins.yml` and `plugins.txt` live inside the AMI. Editing them locally does nothing until you do step 4 or rebuild the AMI.
- Every variable in `jenkins.env` must be filled. One missing value stops the rest of the credentials from loading.
- `COSIGN_PRIVATE_KEY` must be single line base64.
- Check with `sudo journalctl -u jenkins | grep -i casc`

Rebuild AMI (permanent fix instead of step 4)

```bash
cd 00_Setup/Infra/packer
packer build .
# copy artifact_id from manifest.json into terraform/terraform.tfvars
cd ../terraform && terraform apply
```

Destroy

```bash
./jenkins_nodes_setup.sh destroy
./jenkins_nodes_setup.sh destroy --delete-ami
```
