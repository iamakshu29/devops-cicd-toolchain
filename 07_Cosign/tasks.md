# 07 — Cosign: Container Image Signing

> Cryptographic proof that an image came from your pipeline and was not tampered with afterward.
> Closes the gap between "image was scanned" and "image running in production is the same one that was scanned."

---

## What It Is + Why It Matters

Cosign (by Sigstore) signs container images using cryptographic keys or OIDC identity (keyless). The signature is stored alongside the image in the registry (as a special tag). Before deploying, you can verify the image has a valid signature — proving it passed your CI/CD process and was not replaced or tampered with.

**The problem it solves:** Without signing, an attacker who gains write access to your registry could push a malicious image with the same tag. Kubernetes would pull it and run it. Signing proves that only entities with the private key (your pipeline) created the image.

**In your pipeline:**
1. Jenkins builds and scans the image (Trivy, OWASP DC all pass)
2. Jenkins pushes the image to Nexus
3. Jenkins signs the image in Nexus using Cosign — a signature is stored in Nexus next to the image
4. Before K8s runs the image (via Kyverno policy), the signature is verified

---

## How It Works

```
Jenkins Pipeline (after push to Nexus):
      │
      ▼
cosign sign --key cosign.key nexus:8082/sample-app:42
      │
      │  1. Cosign reads the image's digest from the registry
      │     (digest is the sha256 hash of the image manifest — immutable)
      │  2. Signs the digest using your private key
      │  3. Pushes the signature to the registry as a separate artifact
      │     Stored at: nexus:8082/sample-app:sha256-<digest>.sig
      │
      ▼
Registry now has:
  sample-app:42                          ← the image
  sample-app:sha256-abc123...def.sig     ← the signature artifact

At deploy time (Kyverno or manual verify):
      │
      ▼
cosign verify --key cosign.pub nexus:8082/sample-app:42
      │
      │  1. Fetches the signature artifact from the registry
      │  2. Verifies the signature was created with the matching private key
      │  3. Confirms the image digest matches what was signed
      │     If anything in the image changed after signing, verification fails
```

**Key point:** Cosign signs the **image digest** (sha256 hash), not the tag. Tags are mutable (`:latest` can be re-pushed). The digest is immutable — it changes if even one byte of the image changes.

---

## Key Concepts to Know

### Two Signing Modes

**1. Key-based signing (what this path uses)**
- You generate a key pair (`cosign.key` / `cosign.pub`). Store the private key securely in Jenkins credentials to sign the image.
- Distribute the public key to anyone who needs to verify.

**2. Keyless signing (Sigstore/Fulcio)**
Uses OIDC identity (GitHub Actions, GitLab CI, Google Cloud Build) as the signing identity. No key to manage. The signature is anchored to a transparency log (Rekor). Only works with cloud CI/CD systems that issue OIDC tokens — not with self-hosted Jenkins in the same straightforward way.

For self-hosted Jenkins: use **key-based signing**.

---

## Infrastructure Setup

No server. Just a binary.

```bash
# Install on the Jenkins agent (Ubuntu)
COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest \
  | grep tag_name | cut -d '"' -f 4)

curl -Lo cosign \
  "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"

chmod +x cosign
sudo mv cosign /usr/local/bin/cosign
cosign version
```

---

## Generating the Key Pair

Run this once to generate your signing keys:

```bash
# Generates cosign.key (private) and cosign.pub (public)
cosign generate-key-pair
# You will be prompted for a password to protect the private key
# Enter a strong password — you will need it when signing
```

This creates:
- `cosign.key` — private key (NEVER commit to Git, NEVER expose)
- `cosign.pub` — public key (safe to distribute and commit to Git for verification)

**Store `cosign.key` in Jenkins:**
1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. Add credential:
   - Kind: **Secret file**
   - File: upload `cosign.key`
   - ID: `cosign-private-key`
   - Description: `Cosign image signing private key`

**Store the password in Jenkins (if you set one):**
1. Add another credential:
   - Kind: **Secret text**
   - Secret: the password you entered during `generate-key-pair`
   - ID: `cosign-key-password`

---

## Signing the Image

From your Terminal

```bash
cosign sign --key cosign.key --yes registry.example.com/sample-app:v1
# OR
# Use immutable image digest instead of tag (Recommended)
cosign sign --key cosign.key --yes registry.example.com/sample-app:@sha256:<DIGEST>
```
---

## Getting the Image Digest

Tags are mutable — you can push a new image with the same tag. The digest (`sha256:<hash>`) is the immutable fingerprint of the exact image content. Cosign is deprecating tag-based signing because if the tag is re-pushed after signing, the signature no longer matches. Always sign the digest.

After `docker push` the local daemon knows the digest assigned by the registry:

```bash
# Returns the full digest reference: nexus:8082/sample-app@sha256:abc123...
# This is the format cosign sign expects — image name + digest in one string
docker inspect --format='{{index .RepoDigests 0}}' nexus:8082/sample-app:42

# For Jenkins use it like this
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$image:$tag")

# | cut -d'@' -f2 extracts only the hash: sha256:abc123...
# Use this if you need just the hash to construct the ref yourself
docker inspect --format='{{index .RepoDigests 0}}' nexus:8082/sample-app:42 | cut -d'@' -f2
```

This only works **after** the image has been pushed (RepoDigests is empty before push). If the image was just built and pushed in the same pipeline, the digest is available immediately in the same shell session.

---

## The Jenkinsfile Stage

```groovy
stage('Cosign — Sign Image') {
    steps {
        withCredentials([
            file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY'),
            string(credentialsId: 'cosign-key-password', variable: 'COSIGN_PASSWORD')
        ]) {
            sh '''
                echo "Getting Digest"
                DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE_NAME}:${IMAGE_TAG}")

                echo "Signing Image"
                COSIGN_PASSWORD=${COSIGN_PASSWORD} \
                cosign sign --key ${COSIGN_KEY} --yes --allow-insecure-registry ${DIGEST}
            '''
        }
    }
}
```

**`--yes`** skips the interactive confirmation prompt (required for non-interactive CI environments).
**`--allow-insecure-registry`** is required when Nexus uses HTTP (not HTTPS).

**The image must already be in the registry** (pushed to Nexus in the previous stage) before you can sign it. Cosign needs to reach the registry to fetch the digest.

---

## Verifying the Signature

From your terminal (or as a pipeline verification stage):

```bash
cosign verify --key cosign.pub nexus:8082/sample-app:42
# OR
# Use immutable image digest instead of tag (Recommended)
cosign verify --key cosign.pub registry.example.com/sample-app:@sha256:<DIGEST>

```

Output on success:
```
Verification for nexus:8082/sample-app:42 --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - The signatures were verified against the specified public key

[{"critical":{"identity":{"docker-reference":"nexus:8082/sample-app"},"image":{"docker-manifest-digest":"sha256:abc..."},"type":"cosign container image signature"},...}]
```

Output on failure (image was modified after signing):
```
Error: no matching signatures: failed to verify signature
```

---

## Using Cosign With Kyverno (The Full Chain)

This is where Cosign and Kyverno work together. Kyverno can verify the Cosign signature as part of its admission policy — before allowing the pod to start:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-cosign-signature
      match:
        any:
          - resources:
              kinds: [Pod]
      verifyImages:
        - imageReferences:
            - "nexus:8082/sample-app:*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      <paste contents of cosign.pub here>
                      -----END PUBLIC KEY-----
```

With this policy active, any pod using `nexus:8082/sample-app:*` that does NOT have a valid Cosign signature is **rejected at admission time** — before the container even starts. This closes the loop: even if someone manually pushes an unsigned image to Nexus, K8s refuses to run it.

---

## Verification

After the sign stage runs:
```bash
# List all tags for your image in Nexus — you should see the .sig tag
curl -u jenkins-deployer:password \
  http://localhost:8082/v2/sample-app/tags/list
# Returns something like:
# {"name":"sample-app","tags":["42","latest","sha256-abc123...def.sig"]}
```

Or verify directly:
```bash
cosign verify --key cosign.pub nexus:8082/sample-app:42
```

---

## Common Errors + Debugging

### 1. `Error: signing nexus:8082/sample-app:42: GET ... 401 Unauthorized`
**Cause:** Cosign needs registry credentials to fetch the image digest and push the signature artifact
**Fix:** Log in to the registry before running cosign, or set credentials via environment:
```bash
REGISTRY_USERNAME=jenkins-deployer REGISTRY_PASSWORD=pass \
  cosign sign --key cosign.key nexus:8082/sample-app:42
```

### 2. `Error: cosign requires HTTP with registries that use HTTP`
**Cause:** Nexus uses HTTP (not HTTPS), and Cosign defaults to HTTPS
**Fix:** Add `--allow-insecure-registry` flag:
```bash
cosign sign --key cosign.key --allow-insecure-registry nexus:8082/sample-app:42
```

### 3. `Error: private key requires a password`
**Cause:** Key was generated with a password but `COSIGN_PASSWORD` env var is not set
**Fix:** Set `COSIGN_PASSWORD` environment variable before running cosign, or generate a passwordless key for CI: `cosign generate-key-pair` and press Enter when prompted for password

### 4. Signature verification fails even though nothing changed
**Cause 1:** Wrong public key being used for verification
**Cause 2:** Image was re-pushed with the same tag after signing — the digest changed, signature is now invalid
**Fix:** Never re-push to a signed tag. Use immutable tags (build number) rather than `latest` for production images.

---

## Break It on Purpose

**1. Tamper with the image after signing**
Sign the image at `nexus:8082/sample-app:42`.
Then add a new label to the image and re-push it with the same tag:
```bash
docker tag nexus:8082/sample-app:42 nexus:8082/sample-app:42-temp
docker build --label "tampered=yes" -t nexus:8082/sample-app:42 .
docker push nexus:8082/sample-app:42
```
Now verify: `cosign verify --key cosign.pub nexus:8082/sample-app:42`
Observe: verification fails — the image digest changed when the tag was re-pushed.
This is the core value of Cosign. The signature is now invalid and any Kyverno policy enforcing verification will block this image.

**2. Verify with the wrong public key**
Generate a second key pair: `cosign generate-key-pair` → saves as `cosign2.key` / `cosign2.pub`
Verify the image using `cosign2.pub` instead of `cosign.pub`:
```bash
cosign verify --key cosign2.pub nexus:8082/sample-app:42
```
Observe: `no matching signatures` error. The signature exists in the registry but was not made by the key you are verifying against.

**3. Try to deploy an unsigned image with the Kyverno verify policy active**
Push an image to Nexus without running the Cosign sign stage.
Apply the `verify-image-signature` ClusterPolicy (from `08_Kyverno_Policies`).
Try to deploy a pod using the unsigned image:
```bash
kubectl apply -f k8s/deployment.yaml
```
Observe: admission rejected — Kyverno denies the pod with an error like `image signature verification failed`.
Fix: run the Cosign sign stage, then redeploy.

---

## Scenario — The Full Chain: Sign → Verify → Block

This is the end-to-end flow that shows Cosign working as intended.

**Setup:** Kyverno `verify-image-signature` ClusterPolicy is active in Enforce mode.

**Scenario:** A developer directly pushes a "hotfix" image to Nexus bypassing the Jenkins pipeline (they have Nexus credentials). They manually update the image tag in the GitOps repo. ArgoCD syncs.

**What happens:**
```bash
# ArgoCD attempts to deploy the pod
# Kyverno intercepts the Pod admission
# Kyverno fetches the signature from Nexus for the hotfix image tag
# No signature found → Kyverno rejects the pod
# ArgoCD sync fails: "admission webhook denied the request"
```

**Your task:** Reproduce this scenario:
1. Push an image to Nexus without signing it
2. Update the image tag in the GitOps deployment YAML
3. Apply it: `kubectl apply -f k8s/deployment.yaml`
4. Read the exact Kyverno rejection message
5. Sign the image with Cosign
6. Retry the deployment — it should now succeed

This is the pipeline value of Cosign: not just "we sign images" but "unsigned images physically cannot run in our cluster."

---

## Growing Pipeline Snapshot (After This Tool)

```groovy
pipeline {
    agent any
    environment {
        SONAR_PROJECT   = 'sample-app'
        NEXUS_REGISTRY  = 'nexus:8082'
        IMAGE_NAME      = "${NEXUS_REGISTRY}/sample-app"
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
    }
    stages {
        stage('Checkout') {
            steps { git branch: 'main', url: 'https://github.com/your-org/sample-app.git' }
        }
        stage('Checkov — IaC Scan') {
            steps { sh 'checkov -d terraform/ --framework terraform --compact --soft-fail' }
        }
        stage('Build') {
            steps { sh 'mvn clean package -DskipTests' }
        }
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh "mvn sonar:sonar -Dsonar.projectKey=${SONAR_PROJECT}"
                }
            }
        }
        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }
        stage('OWASP Dependency Check') {
            steps {
                dependencyCheck additionalArguments: '--scan ./ --format XML',
                                odcInstallation: 'Dependency-Check'
                dependencyCheckPublisher pattern: 'dependency-check-report.xml',
                                         failedTotalCritical: 1
            }
        }
        stage('Docker Build') {
            steps { sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ." }
        }
        stage('Trivy — Image Scan') {
            steps {
                sh """
                    trivy image --exit-code 1 --severity HIGH,CRITICAL \
                      --ignore-unfixed ${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
        }
        stage('Push to Nexus') {
            steps {
                script {
                    docker.withRegistry("http://${NEXUS_REGISTRY}", 'nexus-credentials') {
                        docker.image("${IMAGE_NAME}:${IMAGE_TAG}").push()
                        docker.image("${IMAGE_NAME}:${IMAGE_TAG}").push('latest')
                    }
                }
            }
        }
        stage('Cosign — Sign Image') {
            steps {
                withCredentials([
                    file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY'),
                    string(credentialsId: 'cosign-key-password', variable: 'COSIGN_PASSWORD')
                ]) {
                    sh '''
                        DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE_NAME}:${IMAGE_TAG}")
                        COSIGN_PASSWORD=${COSIGN_PASSWORD} \
                        cosign sign --key ${COSIGN_KEY} --yes \
                          --allow-insecure-registry ${DIGEST}
                    '''
                }
            }
        }
    }
}
```

---

## Interview Questions

**Q: What problem does Cosign solve?**
A: It provides cryptographic proof that a container image was built by a specific pipeline and was not tampered with afterward. Without signing, an attacker with registry write access could push a malicious image under the same tag and K8s would run it. Cosign's signature is bound to the immutable image digest — if any byte of the image changes, verification fails.

**Q: What is the difference between signing by tag vs by digest?**
A: Cosign always signs the image digest (sha256 hash of the image manifest), not the tag. Tags are mutable — `:latest` can be re-pushed with a different image. The digest is immutable. Signing the digest means the signature is invalid if the image content changes, even if the tag stays the same.

**Q: Where is the Cosign signature stored?**
A: In the same container registry as the image, as a separate artifact. Cosign pushes the signature to a tag derived from the image digest, like `sha256-<digest>.sig`. No separate server or database is needed — the registry stores both the image and its signature.

**Q: How does Cosign integrate with Kyverno?**
A: Kyverno's `ClusterPolicy` can have a `verifyImages` rule that references a public key. Before any pod is admitted to the cluster, Kyverno fetches the Cosign signature from the registry and verifies it against the public key. If the image has no valid signature or the signature is invalid, the pod is rejected at admission time.

**Q: What is keyless signing in Cosign?**
A: Instead of using a private key, keyless signing uses your OIDC identity (from GitHub Actions, GitLab, Google Cloud) as the signing identity. The signature is logged to Sigstore's public transparency log (Rekor). Best for cloud-hosted CI/CD. For self-hosted Jenkins, key-based signing is more practical.
