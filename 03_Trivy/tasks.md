# 03 — Trivy: Container Image Vulnerability Scanner

> Scans the Docker image you just built for OS-level and library-level vulnerabilities.
> Stateless CLI tool — no server, no database to manage, simplest tool to integrate.

---

## What It Is + Why It Matters

Trivy (by Aqua Security) is a vulnerability scanner that inspects a **container image** layer by layer. It checks every OS package (apt, yum), every application library (jar files, pip packages, npm packages) inside the image against its vulnerability database.

**What Trivy scans:**
- OS base image packages (Ubuntu/Debian/Alpine/RHEL packages)
- Application dependencies copied into the image (jar files, node_modules, site-packages)
- Dockerfile misconfigurations (when using `--scanners misconfig`)
- Secret exposure in image layers (when using `--scanners secret`)

---

## How It Works

```
Jenkins Pipeline
      │
      ▼
Docker build produces: nexus:8082/sample-app:42
      │
      ▼
Trivy CLI (runs on Jenkins agent — no server needed)
      │
      │  1. Pulls the image from local Docker daemon (image was just built)
      │  2. Extracts all image layers
      │  3. Downloads/updates its vulnerability database from GitHub
      │     (ghcr.io/aquasecurity/trivy-db — cached after first download)
      │  4. Scans each layer for:
      │     - OS packages: reads /var/lib/dpkg/status (Debian) or equivalent
      │     - App libraries: reads lock files and installed packages inside image
      │  5. Generates report in your chosen format (table, JSON, SARIF)
      │  6. Exits with code 0 (no vulns at threshold) or 1 (vulns found)
      │
      ▼
Jenkins reads exit code → pass or fail the stage
```

**Exit code is how you fail the build.** `--exit-code 1` tells Trivy to exit with code 1 if it finds vulnerabilities at the specified severity. Jenkins treats any non-zero exit code as a stage failure.

---

## Infrastructure Setup

No server. No Docker Compose. Just install the binary on the machine where Jenkins agent runs.

### Install on Windows using choco (Run as admin)
```powershell
choco install trivy -y
```

### Install on Ubuntu/Debian (Jenkins agent)
```bash
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy
trivy --version
```

### Install on RHEL/CentOS
```bash
sudo rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.52.0/trivy_0.52.0_Linux-64bit.rpm
trivy --version
```

### Run as Docker (if you cannot install on the agent)
```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $HOME/.cache/trivy:/root/.cache/trivy \
  aquasec/trivy:latest image <your-image>
```
Mounting `/var/run/docker.sock` allows Trivy container to access the host's Docker daemon and scan images.

---

## Understanding the Key Flags

These flags are what interviewers ask about. Know what each one does.

```bash
trivy image \
  --exit-code 1 \               # exit 1 if vulnerabilities found (fails Jenkins stage)
  --severity HIGH,CRITICAL \    # only report/fail on HIGH and CRITICAL (ignore LOW/MEDIUM)
  --ignore-unfixed \            # skip vulns that have no fix available yet
  --format json \              # output format: table (default) | json | sarif | cyclonedx
  --output trivy-report.json \  # save report to file (omit to print to stdout)
  --cache-dir /tmp/trivy-cache \ # where to cache the vulnerability database
  nexus:8082/sample-app:42
```

**`--ignore-unfixed` is important:** Many OS vulnerabilities have no available fix yet. Without this flag, every Ubuntu base image will have dozens of unfixable LOW/MEDIUM findings that fail your build even though you cannot do anything about them. Most teams set `--severity HIGH,CRITICAL --ignore-unfixed` to focus on what can actually be fixed.

**`--severity` controls both reporting AND the exit code.** If you set `--severity HIGH,CRITICAL`, Trivy only reports those levels and only exits with code 1 if those levels are found.

---

## The Jenkinsfile Stage

```groovy
stage('Trivy — Image Scan') {
    steps {
        sh """
            trivy image \
              --exit-code 1 \
              --severity HIGH,CRITICAL \
              --ignore-unfixed \
              --format json \
              --output trivy-report.json \
              --cache-dir /var/cache/trivy \
              ${IMAGE_NAME}:${IMAGE_TAG}
        """
    }
    post {
        always {
            // Archive the report even if the build failed
            archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
        }
    }
}
```

**`--output trivy-report.json` Save the report as an artifact**

**`--exit-code 0` Scan with soft-fail (report but never fail the build, just report):**
- Use this when first introducing Trivy to a pipeline where the existing image has findings — you want to see the report without blocking CI immediately.

### Scanning Terraform / IaC files (not just images)

```groovy
stage('Trivy — IaC Scan') {
    steps {
        sh "trivy config --exit-code 1 --severity HIGH,CRITICAL ./terraform/"
    }
}
```

This overlaps with Checkov. Some teams use only Trivy for both IaC and image scanning to reduce tool count.

---

## Verification

After the pipeline runs:
1. Check the Jenkins console log for the Trivy output table — it shows each vulnerability, package, severity, and installed vs fixed version
2. A passing scan looks like:
   ```
   Total: 0 (HIGH: 0, CRITICAL: 0)
   ```
3. A failing scan shows a table with findings and then:
   ```
   FATAL   exit status 1
   ```
   Which causes the Jenkins stage to fail

Check that `trivy-report.json` appears in the Jenkins build artifacts if you configured `archiveArtifacts`.

---

## Common Errors + Debugging

### 1. `Error: failed to initialize source: ... unauthorized`
**Error:** Trivy cannot pull the image to scan it
**Cause:** The image is on private registry and Trivy is trying to pull it without credentials
**Fix:** Either scan the image from the local Docker daemon (it was just built and is locally available), or pass registry credentials:
```bash
TRIVY_USERNAME=jenkins TRIVY_PASSWORD=yourpass trivy image nexus:8082/sample-app:42
```

### 2. Database download takes very long
**Cause:** Trivy downloads its vulnerability database from GitHub on first run (and every 12 hours by default)
**Fix:** Use `--cache-dir /var/cache/trivy` in the pipeline command. The directory is created during AMI build (Packer) and owned by the `jenkins` user, so no sudo is needed at runtime.
```bash
trivy image --cache-dir /var/cache/trivy ${IMAGE_NAME}:${IMAGE_TAG}
```

### 3. Build fails on LOW/MEDIUM vulnerabilities you did not expect
**Cause:** `--severity` was not set, so Trivy reports and fails on all severity levels including LOW
**Fix:** Add `--severity HIGH,CRITICAL` to focus only on actionable findings

### 4. `Cannot connect to the Docker daemon`
**Cause:** The Jenkins agent user does not have permission to access the Docker socket
**Fix:** Add the Jenkins user to the `docker` group:
```bash
sudo usermod -aG docker jenkins
# Restart Jenkins service for group change to take effect
sudo systemctl restart jenkins
```

### 5. Trivy finds vulnerabilities in the base image you cannot fix
**Cause:** The Ubuntu/Debian base image itself has unfixed OS vulnerabilities
**Fix 1:** Use `--ignore-unfixed` to skip vulnerabilities with no available patch
**Fix 2:** Use a smaller base image — Alpine Linux has a much smaller attack surface than Ubuntu
**Fix 3:** Use distroless images (Google's `gcr.io/distroless/java`) — they have no shell, no package manager, minimal attack surface

---

## Interview Questions

**Q: Why does Trivy run after Docker build and not before?**
A: Trivy scans the container image — OS packages, runtime libraries, everything inside the image layers. Those only exist after the image is built. You cannot scan what doesn't exist yet.

**Q: What is the difference between Trivy and OWASP Dependency Check?**
A: OWASP DC scans your application's declared dependencies (pom.xml, requirements.txt) before a Docker image is built. Trivy scans the final container image including OS packages and every library inside it. OWASP DC catches library CVEs early; Trivy catches OS-level and image-level vulnerabilities after build.

**Q: How do you fail a Jenkins build if Trivy finds a critical vulnerability?**
A: Use `--exit-code 1` combined with `--severity HIGH,CRITICAL`. Trivy exits with code 1 when it finds vulnerabilities at the specified severity. Jenkins treats any non-zero exit code as a stage failure.

**Q: There are 50 unfixable OS vulnerabilities in the base image. How do you handle this?**
A: Use `--ignore-unfixed` flag — Trivy skips vulnerabilities that have no available fix. Additionally, consider switching to a minimal base image (Alpine or distroless) which has far fewer OS packages and a much smaller attack surface.

**Q: How do you keep Trivy's database up to date in a CI/CD pipeline?**
A: Trivy auto-downloads its database from GitHub on first run and refreshes it every 12 hours by default. Use `--cache-dir /var/cache/trivy` in your pipeline command. The directory must be pre-created and owned by the jenkins user — if it doesn't exist, Trivy tries to create it ownd directory if --cache-dir flag is mentioned, which requires root, and the pipeline fails with a permission error because jenkins has no sudo access.
```bash
sudo mkdir -p /var/cache/trivy
sudo chown jenkins:jenkins /var/cache/trivy
```

**Q: How can we ensure that the Docker image is built with fewer vulnerabilities from the beginning, instead of discovering many issues only after running Trivy?**
A: Use a minimal and regularly updated base image and scan the image as part of the build process.
- This is why "use a minimal base image like alpine or distroless" is real security advice, not just a performance tip.
**Q: How can we ensure that vulnerabilities fixed in a previous build are properly re-scanned and do not reappear in subsequent builds?**
A: Run Trivy on every new image build, including after updating the base image or application dependencies.
- Also, use digest pinning for the base image to ensure the same, verified image is used consistently.
- Tags such as ubuntu:22.04 are mutable and can point to a different image over time. Digest pinning ensures that the exact base image that was scanned and approved is used again.