# 09 — ArgoCD: GitOps Continuous Deployment

> Jenkins owns CI — build, scan, push. ArgoCD owns CD — deploy to K8s, watch for drift, roll back.
> The handoff point: Jenkins commits the new image tag to the GitOps repo. ArgoCD detects it and syncs the cluster.

---

## What It Is + Why It Matters

ArgoCD is a declarative GitOps continuous delivery tool for Kubernetes. It watches a Git repository containing your K8s manifests. When the manifests change, ArgoCD automatically syncs the cluster to match.

**The problem it solves:** Without ArgoCD, Jenkins would need direct `kubectl` access to the cluster to deploy — tightly coupling CI and CD, making rollbacks manual, and giving your build server cluster-admin access. ArgoCD separates these concerns cleanly.

**In your pipeline:**
1. Jenkins builds, scans, signs the image (CI is complete)
2. Jenkins commits an updated image tag to the GitOps repo (`k8s/deployment.yaml`)
3. ArgoCD detects the commit → pulls the updated manifests → applies them to the cluster
4. Kyverno admission policies run as the pod is created (signature check, policy enforcement)

---

## How It Works

```
Jenkins Pipeline (after cosign sign):
      │
      ▼
Stage: Update GitOps Repo
  git clone gitops-repo
  sed -i image tag in k8s/deployment.yaml
  git commit + push
      │
      ▼
ArgoCD (watching gitops-repo):
  detects new commit
      │
      ▼
ArgoCD syncs cluster:
  kubectl apply -f k8s/deployment.yaml  (effectively)
      │
      ▼
Kyverno admission webhook:
  verifies cosign signature on image
  checks pod security policies
      │
      ▼
Pod starts, Vault Agent Injector injects secrets
```

---

## Two Repos Pattern (GitOps Best Practice)

```
app-repo (GitHub)          gitops-repo (GitHub)
┌──────────────────┐       ┌──────────────────────────┐
│ src/             │       │ k8s/                     │
│ Dockerfile       │  CI   │   deployment.yaml        │
│ Jenkinsfile      │ ────► │   service.yaml           │
│ terraform/       │ updates│   ingress.yaml           │
└──────────────────┘  tag  └──────────────────────────┘
                                      ▲
                                      │ watches
                                   ArgoCD
```

**Why two repos:**
- App repo changes trigger CI (build, test, scan)
- GitOps repo changes trigger CD (ArgoCD sync)
- Audit trail: every deployment is a Git commit with who changed what
- Rollback = `git revert` — no special tooling needed

---

## Infrastructure Setup

ArgoCD runs inside the K8s cluster.

```bash
# Install ArgoCD into its own namespace
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s

# Get initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d

# Access the UI (port-forward or LoadBalancer)
kubectl port-forward svc/argocd-server -n argocd 8443:443
# Open: https://localhost:8443  (username: admin)
```

---

## Creating an ArgoCD Application

Via UI: New App → fill in repo URL, path, cluster, namespace.

Via manifest (GitOps way — apply this to the cluster):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo.git
    targetRevision: main
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
  syncPolicy:
    automated:
      prune: true       # delete resources removed from Git
      selfHeal: true    # revert manual kubectl changes
```

**`automated` sync** means ArgoCD syncs automatically on every commit — no manual "Sync" button needed.
**`selfHeal: true`** means if someone manually edits a resource in the cluster, ArgoCD reverts it back to Git state within 3 minutes (drift detection).

---

## The Jenkinsfile Stage

```groovy
stage('Update GitOps Repo') {
    steps {
        withCredentials([usernamePassword(
            credentialsId: 'github-credentials',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
        )]) {
            sh '''
                git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/your-org/gitops-repo.git
                cd gitops-repo
                sed -i "s|image: .*sample-app.*|image: ${IMAGE_NAME}:${IMAGE_TAG}|" k8s/deployment.yaml
                git config user.email "jenkins@ci.local"
                git config user.name "Jenkins"
                git commit -am "ci: update image tag to ${IMAGE_TAG} [skip ci]"
                git push
            '''
        }
    }
}
```

**`[skip ci]`** in the commit message — prevents the commit from triggering a new Jenkins build if Jenkins is also watching the GitOps repo.

---

## Sync Policies

| Policy | Behaviour |
|--------|-----------|
| Manual | ArgoCD detects drift but waits for you to click Sync |
| Automated | Syncs on every Git commit automatically |
| `prune: true` | Deletes K8s resources that were removed from Git |
| `selfHeal: true` | Reverts manual cluster changes back to Git state |

For a learning setup: automated + prune + selfHeal gives you full GitOps behaviour.

---

## Rollback

Because every deployment is a Git commit, rollback is a Git operation:

```bash
# Option 1: revert the image tag commit in gitops-repo
git revert HEAD
git push
# ArgoCD detects the revert → deploys the previous image tag

# Option 2: use ArgoCD UI → History → select previous revision → Rollback
# Option 3: use argocd CLI
argocd app rollback sample-app
```

---

## Common Errors + Debugging

### 1. ArgoCD cannot clone the GitOps repo
**Cause:** Private repo, no credentials configured in ArgoCD
**Fix:** Settings → Repositories → Connect Repo → add GitHub PAT or SSH key

### 2. Sync stuck in `Progressing`
**Cause:** Pod failing to start (image pull error, CrashLoopBackOff)
**Fix:** Check pod events: `kubectl describe pod <pod> -n sample-app`

### 3. `ComparisonError` — cannot apply manifest
**Cause:** YAML syntax error in the manifest Jenkins just committed
**Fix:** Check the exact diff in ArgoCD UI → App Details → Diff tab

### 4. ArgoCD reverts your manual `kubectl` changes immediately
**Cause:** `selfHeal: true` is active — this is expected behaviour
**Fix:** Make the change in Git, not directly in the cluster

---

## Interview Questions

**Q: What is GitOps?**
A: A practice where the desired state of your infrastructure and deployments is stored in Git. Git is the single source of truth. Changes are made via Git commits, and an operator (ArgoCD) continuously reconciles the cluster to match Git state.

**Q: What is the difference between push-based and pull-based CD?**
A: Push-based (e.g. Jenkins running `kubectl apply` directly): CI server pushes changes to the cluster — requires cluster-admin credentials on the build server, tight coupling. Pull-based (ArgoCD): the agent inside the cluster watches Git and pulls changes — build server never has cluster access, more secure.

**Q: What does ArgoCD do when someone manually changes a resource in the cluster?**
A: With `selfHeal: true`, ArgoCD detects the drift (compares cluster state to Git) and reverts the manual change back to Git state within ~3 minutes. This enforces Git as the only way to change production.

**Q: How does ArgoCD trigger after Jenkins pushes a new image tag?**
A: Jenkins commits the updated `deployment.yaml` (with new image tag) to the GitOps repo. ArgoCD polls the repo every 3 minutes by default, or can be triggered immediately via a webhook from GitHub. It detects the new commit, computes the diff, and applies the updated manifest to the cluster.

**Q: What is the difference between ArgoCD and Flux?**
A: Both are GitOps CD tools. ArgoCD has a rich UI, multi-cluster support, and app-of-apps pattern. Flux is more CLI-driven and follows a stricter GitOps model. ArgoCD is more commonly used in companies for its visibility and multi-team support.
