# CI/CD Pipeline — Architecture Reference

> Read this once before starting any tool. Understand the full picture, then work through tools one by one.

---

## The Complete Pipeline Flow

```
Developer pushes code to GitHub
         │
         ▼
  ┌─────────────────────────────────────────────────────────────────────────┐
  │                        JENKINS PIPELINE                                  │
  │                                                                           │
  │  Stage 1: Checkout                                                        │
  │    └── git clone from GitHub                                              │
  │                                                                           │
  │  Stage 2: Checkov — IaC Scan (early, before any build)                   │
  │    └── checkov -d terraform/ → fail if Terraform has misconfigs           │
  │                                                                           │
  │  Stage 3: Build                                                           │
  │    └── mvn clean package (compiles app, runs unit tests)                 │
  │                                                                           │
  │  Stage 4: SonarQube Analysis                                              │
  │    └── Scanner sends code to SonarQube Server → analysis runs async       │
  │                                                                           │
  │  Stage 5: Quality Gate (waits for SonarQube webhook callback)            │
  │    └── abortPipeline: true if gate fails                                  │
  │                                                                           │
  │  Stage 6: OWASP Dependency Check                                          │
  │    └── scans pom.xml / requirements.txt for CVEs against NVD database     │
  │                                                                           │
  │  Stage 7: Docker Build                                                    │
  │    └── docker build -t nexus:8082/sample-app:${BUILD_NUMBER} .           │
  │                                                                           │
  │  Stage 8: Trivy — Image Scan                                              │
  │    └── trivy image --exit-code 1 --severity HIGH,CRITICAL <image>        │
  │                                                                           │
  │  Stage 9: Push to Nexus                                                   │
  │    └── docker push to Nexus Docker hosted repository                      │
  │                                                                           │
  │  Stage 10: Cosign — Sign Image                                            │
  │    └── cosign sign --key cosign.key nexus:8082/sample-app:${BUILD_NUMBER} │
  │                                                                           │
  │  Stage 11: Update GitOps Repo                                             │
  │    └── git commit: update image tag in k8s/deployment.yaml               │
  │                                                                           │
  │  post { success: slack green } { failure: slack red }                    │
  └─────────────────────────────────────────────────────────────────────────┘
         │
         ▼
  ArgoCD detects change in GitOps repo
         │
         ▼
  Kyverno ClusterPolicies run as admission webhook
    └── block if image not from Nexus, block if running as root
         │
         ▼
  Pod starts → Vault Agent Injector sidecar injects secrets
    └── app reads secrets from /vault/secrets/ — no env vars, no K8s secrets in Git
         │
         ▼
  App is live, Prometheus scrapes metrics, Grafana shows dashboard
```

---

## Tool Responsibilities — Who Does What

| Tool | Stage | What it actually checks |
|------|-------|------------------------|
| Checkov | Before build | Does your Terraform/K8s YAML have security misconfigs? (open S3 bucket, no encryption, root IAM) |
| SonarQube | After build | Does your source code have bugs, vulnerabilities, code smells, or low coverage? |
| OWASP DC | After build | Do your app's dependencies (libraries) have known CVEs? |
| Trivy | After Docker build | Does the container image have OS or library vulnerabilities? |
| Nexus | After scan passes | Central registry to store and version your Docker images |
| Cosign | After push | Cryptographic proof that this image came from this pipeline and was not tampered with |
| Vault | Runtime (K8s pod) | Injects DB passwords, API keys into pods — secrets never in Git or K8s Secret YAML |
| Kyverno | K8s admission time | Policy enforcement — rejects pods that violate cluster-wide rules |
| Notifications | post block | Tells your team whether the build passed or failed |

---

## How Tools Authenticate With Each Other

This is what breaks most often when you wire things together.

```
Jenkins → SonarQube
  Auth method: Token (Project Analysis Token generated in SonarQube UI)
  Stored in Jenkins as: Secret Text credential
  Used in Jenkinsfile via: withSonarQubeEnv('SonarQube') { ... }

Jenkins → Nexus (Docker push)
  Auth method: Username/Password
  Stored in Jenkins as: Username with password credential
  Used in Jenkinsfile via: docker.withRegistry('http://nexus:8082', 'nexus-creds')

Jenkins → GitHub (GitOps repo update)
  Auth method: Personal Access Token or Deploy Key
  Stored in Jenkins as: Username with password (token as password)
  Used in Jenkinsfile via: withCredentials([usernamePassword(...)])

Jenkins → Cosign
  Auth method: Private key file
  Stored in Jenkins as: Secret file credential
  Used in Jenkinsfile via: withCredentials([file(credentialsId: 'cosign-key'...)])

SonarQube → Jenkins (webhook callback)
  Auth method: Jenkins webhook endpoint (no auth by default, can add secret token)
  Configured in: SonarQube UI → Administration → Webhooks
  URL format: http://jenkins:8080/sonarqube-webhook/

Vault → K8s
  Auth method: Kubernetes auth method (pod's ServiceAccount JWT)
  No Jenkins involvement — Vault Agent Injector sidecar handles this at pod startup

Kyverno → K8s API
  Auth method: None needed — runs as admission webhook registered in the cluster
  Applied via: kubectl apply or ArgoCD sync of ClusterPolicy manifests
```

---

## Port Reference

| Service | Port | What listens here |
|---------|------|-------------------|
| Jenkins | 8080 | Web UI + webhook endpoint |
| SonarQube | 9000 | Web UI + API + analysis results |
| Nexus | 8081 | Web UI + REST API |
| Nexus | 8082 | Docker hosted repository (push/pull images here) |
| Vault | 8200 | API + UI |

---

## The Two Things That Are NOT Pipeline Stages

Both get confused as pipeline stages by people who haven't set them up before.

**Vault:**
Vault is NOT a Jenkins pipeline stage. You do not call Vault from a `sh` command in your pipeline.
What actually happens: The pod's YAML has an annotation (`vault.hashicorp.com/agent-inject-secret-*`). When ArgoCD deploys the pod, the Vault Agent Injector (a mutating webhook) intercepts the pod creation, injects a sidecar container, and the sidecar fetches secrets from Vault and writes them to `/vault/secrets/` inside the pod. Your app reads from that path. Jenkins never talks to Vault directly.

**Kyverno:**
Kyverno is NOT a Jenkins pipeline stage. You apply `ClusterPolicy` manifests to the cluster once (via ArgoCD or kubectl). After that, every pod admission — from any source — is checked against those policies by Kubernetes itself at admission time. No Jenkins involvement.

---

## Infrastructure Networking (Docker Compose Scenario)

If you run Jenkins, SonarQube, and Nexus all in Docker on the same machine, they can reach each other by container name if they are on the same Docker network.

```
Jenkins container  →  "http://sonarqube:9000"   (not localhost)
Jenkins container  →  "http://nexus:8082"        (not localhost)
Your browser       →  "http://localhost:9000"    (to open SonarQube UI)
Your browser       →  "http://localhost:8081"    (to open Nexus UI)
```

This is a common confusion: `localhost` from inside a Jenkins container refers to Jenkins itself, not the host machine. Use the Docker container name as the hostname when configuring tool URLs in Jenkins.

---

## What ArgoCD Does in This Pipeline

ArgoCD watches your GitOps repo (a separate repo from your app code).
Your Jenkins pipeline updates the image tag in that GitOps repo (Stage 11 above).
ArgoCD detects the commit, syncs the cluster, and deploys the new image.

This is the **separation of concerns**:
- Jenkins owns CI (build, test, scan, push)
- ArgoCD owns CD (deploy to K8s, drift detection, rollback)

ArgoCD is covered in the ArgoCD section (Step 1 in context.md). This pipeline assumes ArgoCD is already running.

---

## The Full Jenkinsfile (Target — You Will Build This Stage by Stage)

```groovy
// Generated by GitHub Copilot
pipeline {
    agent any

    environment {
        NEXUS_REGISTRY  = 'nexus:8082'
        IMAGE_NAME      = "${NEXUS_REGISTRY}/sample-app"
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
        SONAR_PROJECT   = 'sample-app'
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/your-org/sample-app.git'
            }
        }

        stage('Checkov — IaC Scan') {
            steps {
                sh 'checkov -d terraform/ --framework terraform --soft-fail'
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests'
            }
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
                dependencyCheckPublisher pattern: 'dependency-check-report.xml'
            }
        }

        stage('Docker Build') {
            steps {
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
            }
        }

        stage('Trivy — Image Scan') {
            steps {
                sh """
                    trivy image \
                      --exit-code 1 \
                      --severity HIGH,CRITICAL \
                      --format table \
                      ${IMAGE_NAME}:${IMAGE_TAG}
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
                withCredentials([file(credentialsId: 'cosign-private-key',
                                      variable: 'COSIGN_KEY')]) {
                    sh "cosign sign --key ${COSIGN_KEY} ${IMAGE_NAME}:${IMAGE_TAG}"
                }
            }
        }

        stage('Update GitOps Repo') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                                   usernameVariable: 'GIT_USER',
                                                   passwordVariable: 'GIT_TOKEN')]) {
                    sh """
                        git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/your-org/gitops-repo.git
                        cd gitops-repo
                        sed -i 's|image: .*|image: ${IMAGE_NAME}:${IMAGE_TAG}|' k8s/deployment.yaml
                        git config user.email "jenkins@ci.local"
                        git config user.name "Jenkins"
                        git commit -am "ci: update image tag to ${IMAGE_TAG}"
                        git push
                    """
                }
            }
        }
    }

    post {
        success {
            slackSend channel: '#deployments',
                      color: 'good',
                      message: "PASSED: ${env.JOB_NAME} #${env.BUILD_NUMBER} | <${env.BUILD_URL}|View>"
        }
        failure {
            slackSend channel: '#deployments',
                      color: 'danger',
                      message: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} | <${env.BUILD_URL}|View>"
        }
    }
}
```
