# CI/CD Pipeline — Learning Roadmap

> Goal: Learn each pipeline tool end-to-end — from install to Jenkins integration — so you can set up, debug, and explain every stage in an interview.

---

## What You Already Know

- Jenkins declarative pipelines (Jenkinsfile syntax)
- Conceptual pipeline flow (trigger → build → scan → push → deploy)
- Docker, Terraform, K8s, Ansible basics

## What This Path Adds

You have named these tools in interviews. This path makes you know:
- How each tool is installed and configured
- How it authenticates with Jenkins
- What the exact Jenkinsfile stage looks like and why each option matters
- What breaks during integration and how to fix it

---

## The Reference Application

All Jenkinsfile stages target a simple **Java Spring Boot app (Maven)**.

**Why Java/Maven:** SonarQube, OWASP Dependency Check, and Nexus have the cleanest Maven integration and are the most common combination in company pipelines.

Every tool's tasks.md includes an **"Alternative commands for Python/Node"** note where the command differs.

---

## Tool Order

```
01_SonarQube/                → Most asked in interviews. Most setup complexity. Start here.
02_OWASP_Dependency_Check/   → Scans app libraries for CVEs. Jenkins plugin approach.
03_Trivy/                    → Scans the built Docker image. Stateless, simplest setup.
04_Checkov/                  → Scans Terraform/K8s IaC. No server needed.
05_Nexus/                    → Artifact registry. Jenkins pushes image here, ArgoCD pulls.
06_Vault/                    → Secrets management in K8s. Requires K8s cluster.
07_Cosign/                   → Signs container images. Binary tool, no server.
08_Kyverno_Policies/         → K8s admission policies via manifests. Applied through ArgoCD.
09_Notifications/             → Slack/Teams webhook. Post block in Jenkinsfile.
10_Full_Pipeline_Project/    → Complete wired pipeline: app + Jenkinsfile + ArgoCD + all tools.
```

---

## How the Pipeline Grows (Incrementally)

Each tool adds one stage to the same Jenkinsfile. You are not building isolated demos.

```
Start:         Checkout → Build
After 01:      Checkout → Build → SonarQube Analysis → Quality Gate
After 02:      ... → Quality Gate → OWASP Dependency Check
After 03:      ... → OWASP DC → Docker Build → Trivy Scan
After 04:      Checkov (IaC scan) moves to the top, before Build
After 05:      ... → Trivy Scan → Push to Nexus
After 06:      Vault integration is runtime (K8s pod annotation), not a pipeline stage
After 07:      ... → Push to Nexus → Cosign Sign Image
After 08:      Kyverno policies are applied to the cluster via ArgoCD, not a pipeline stage
After 09:      post { success { slack } failure { slack } }
```

Final pipeline has **8 active stages** + post block.

---

## Infrastructure Overview

Tools that need a running server (Docker recommended for learning):

| Tool | Run as | Port | Notes |
|------|--------|------|-------|
| Jenkins | Docker or native | 8080 | You already have this |
| SonarQube | Docker (+ PostgreSQL) | 9000 | Needs 2GB RAM minimum |
| Nexus | Docker | 8081 (UI), 8082 (Docker repo) | Needs persistent volume |
| Vault | Docker (dev mode) or K8s Helm | 8200 | K8s integration needs Helm chart |

Tools that are just CLIs (installed on Jenkins agent):

| Tool | Install method |
|------|---------------|
| Trivy | Binary or Docker image |
| Checkov | pip install checkov |
| Cosign | Binary download |
| OWASP Dependency Check | Jenkins plugin (installed on agent automatically) |

---

## File Reading Order

```
1. Pipeline-Architecture-Reference.md   → Read once to understand the full picture
2. 01_SonarQube/tasks.md                → Set up SonarQube, run the stage, verify it works
3. 02 → 09 (one at a time)              → Add each tool's stage, verify before moving on
4. 10_Full_Pipeline_Project/tasks.md    → Only after all tools work individually
```

---

## Rules for Yourself

- Set up each tool locally and run its pipeline stage before moving to the next.
- Do not add tool 03 until tool 02 is working in your pipeline.
- Read the **Common Errors** section before you start each tool — not after it breaks.
- The **Interview Questions** at the end of each tasks.md: write your own answer first, then check.
- For tools that say "no server needed" — still read the config options. Interviewers ask about flags.
