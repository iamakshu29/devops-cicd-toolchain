# 06 — Vault: Secrets Management

> Secrets never live in Git, K8s manifests, or environment variables in plain text.
> Vault is the runtime secret injector — pods get secrets only when they start, only if they are authorized.

---

## What It Is + Why It Matters

HashiCorp Vault is a secrets management tool. At its core: you store a secret in Vault (a DB password, API key, TLS cert), and only authorized applications can retrieve it. Vault handles encryption, access control, secret rotation, and audit logging.

**Why not just use Kubernetes Secrets?**
K8s Secrets are only base64-encoded, not encrypted at rest by default. They live in etcd. Anyone with `kubectl get secret` access can decode them. They show up in Git if you commit your manifests. Vault solves all of these problems.

**In your pipeline context:**
Vault is NOT a Jenkins pipeline stage. It operates at **pod runtime** — when ArgoCD deploys your pod to K8s, Vault injects secrets into the pod as the pod starts. Your app never calls Vault directly; it just reads files from `/vault/secrets/`.

---

## The Two Vault Integration Patterns (Know Both)

### Pattern 1 — Vault Agent Injector (Sidecar) — Most Common in K8s

This is what most companies use. No code changes to the application.

```
ArgoCD deploys Pod with annotation:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "sample-app"
  vault.hashicorp.com/agent-inject-secret-config.properties: "secret/sample-app/config"
          │
          ▼
Vault Agent Injector (mutating webhook, running in kube-system)
  └── Intercepts the pod creation request
  └── Injects an init container and a Vault Agent sidecar into the pod spec
          │
          ▼
Init container runs:
  └── Authenticates with Vault using the pod's ServiceAccount JWT (K8s auth method)
  └── Fetches the secret from Vault: secret/sample-app/config
  └── Writes it to /vault/secrets/config.properties inside a shared volume
          │
          ▼
Your app container starts:
  └── Reads /vault/secrets/config.properties
  └── Secret is never in the pod YAML, never in Git, never in a K8s Secret object
```

### Pattern 2 — External Secrets Operator (ESO)

An alternative approach where a K8s controller pulls secrets from Vault and creates K8s Secret objects. The app still reads from K8s Secrets, but the source of truth is Vault. Easier to migrate existing apps to but the secrets still exist in K8s Secret objects.

This path focuses on **Pattern 1 (Vault Agent Injector)** since it is the more secure approach and what most K8s-native setups use.

---

## How the K8s Auth Method Works

This is what "authorizing" a pod to access Vault means:

```
Vault Kubernetes Auth Method:

1. Vault is configured with: vault auth enable kubernetes
2. You tell Vault: "trust the K8s API server at https://kubernetes.default.svc"
3. You create a Vault policy: "policy named 'sample-app-policy' can read secret/sample-app/*"
4. You create a Vault role: "K8s ServiceAccount 'sample-app-sa' in namespace 'default'
                             can use policy 'sample-app-policy'"

At pod start:
5. Vault Agent Injector (init container) presents the pod's ServiceAccount JWT token to Vault
6. Vault calls the K8s API to verify: "is this JWT from a real ServiceAccount?"
7. K8s API says yes
8. Vault issues a short-lived Vault token to the init container
9. Init container uses that token to read the secret
10. Secret is written to /vault/secrets/ and the token is discarded
```

No static long-lived credentials. The pod's own Kubernetes identity is the credential.

---

## Infrastructure Setup

### Option A — Docker (Dev Mode) — For Learning the Concepts

Vault dev mode starts with no persistence and a known root token. Do NOT use in production.

```bash
docker run -d \
  --name vault \
  --cap-add IPC_LOCK \
  -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  hashicorp/vault:latest server -dev
```

Access at `http://localhost:8200`, token: `root`

```bash
# Set env vars to talk to Vault from your terminal
export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN='root'

# Store a secret (KV v2 secrets engine is enabled by default in dev mode)
vault kv put secret/sample-app/config \
  db_password="supersecret" \
  api_key="abc123"

# Read it back
vault kv get secret/sample-app/config
```

### Option B — K8s via Helm (For Integration Practice)

This is what you need for the Vault Agent Injector to work (it needs to run inside K8s).

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.dev.enabled=true"    # dev mode for learning

# Wait for Vault pod to be ready
kubectl -n vault get pods

# Port-forward to access Vault UI
kubectl -n vault port-forward svc/vault 8200:8200 &
```

---

## Full Setup: Vault Agent Injector (K8s Integration)

This is the end-to-end setup to inject secrets into a pod.

### Step 1 — Enable Vault Injector
```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "injector.enabled=true" \
  --set "server.dev.enabled=true"
```
The injector registers itself as a mutating webhook in K8s automatically.

### Step 2 — Enable K8s Auth Method in Vault
```bash
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
```

### Step 3 — Create a Secret in Vault
```bash
kubectl exec -n vault vault-0 -- vault kv put secret/sample-app/config \
  db_password="mysecretpassword" \
  api_key="myapikey123"
```

### Step 4 — Create a Vault Policy
```bash
kubectl exec -n vault vault-0 -- vault policy write sample-app-policy - <<EOF
path "secret/data/sample-app/config" {
  capabilities = ["read"]
}
EOF
```

### Step 5 — Create a K8s Service Account for Your App
```bash
kubectl create serviceaccount sample-app-sa -n default
```

### Step 6 — Create a Vault Role That Links ServiceAccount → Policy
```bash
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/sample-app \
  bound_service_account_names=sample-app-sa \
  bound_service_account_namespaces=default \
  policies=sample-app-policy \
  ttl=1h
```

This says: "A pod using ServiceAccount `sample-app-sa` in namespace `default` can use policy `sample-app-policy` and gets a token valid for 1 hour."

### Step 7 — Annotate Your Deployment
```yaml
# Generated by GitHub Copilot
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "sample-app"
        # The part after agent-inject-secret- becomes the filename in /vault/secrets/
        vault.hashicorp.com/agent-inject-secret-config.properties: "secret/data/sample-app/config"
        # Optional: template the output format
        vault.hashicorp.com/agent-inject-template-config.properties: |
          {{- with secret "secret/data/sample-app/config" -}}
          db.password={{ .Data.data.db_password }}
          api.key={{ .Data.data.api_key }}
          {{- end -}}
    spec:
      serviceAccountName: sample-app-sa   # MUST match the Vault role
      containers:
        - name: app
          image: nexus:8082/sample-app:42
          # App reads /vault/secrets/config.properties — no env vars, no K8s secrets
```

After ArgoCD deploys this pod:
```bash
kubectl exec -it <pod> -- cat /vault/secrets/config.properties
# Should print:
# db.password=mysecretpassword
# api.key=myapikey123
```

---

## What About Jenkins and Vault?

Jenkins does use Vault in some setups — via the **HashiCorp Vault Plugin** — to inject secrets into pipeline environment variables. But in a K8s-native pipeline, this is less common. The typical split:

- **Jenkins** uses its own Credential Store for CI secrets (Nexus credentials, GitHub token, SonarQube token)
- **Vault** handles runtime secrets for the deployed application (DB passwords, API keys the app needs)

Jenkins never needs to talk to Vault in the pipeline described in this path.

---

## Verification

```bash
# Check Vault injector is running
kubectl -n vault get pods
# Should show: vault-agent-injector-xxx   1/1   Running

# Check the mutating webhook is registered
kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg

# After deploying an annotated pod, check the injected secrets
kubectl exec -it <pod-name> -- ls /vault/secrets/
kubectl exec -it <pod-name> -- cat /vault/secrets/config.properties
```

---

## Common Errors + Debugging

### 1. Pod stuck in `Init:0/1` — init container not completing
**Cause:** Vault Agent init container cannot authenticate with Vault
**Debug:** `kubectl logs <pod> -c vault-agent-init`
**Common reasons:**
- ServiceAccount name in deployment does not match the `bound_service_account_names` in the Vault role
- Wrong namespace — role is bound to `default` but pod is in `production`
- Vault is not reachable from the pod (network policy blocking it)

### 2. `permission denied` when reading the secret
**Cause:** The Vault policy does not grant `read` on the secret path, or the path is wrong (KV v2 paths require `secret/data/...` not `secret/...`)
**Fix:** KV v2 secrets engine uses `secret/data/your/path` for policies, not `secret/your/path`. This is a very common mistake.

### 3. Injected file is empty or contains error message
**Cause:** The secret path in the annotation is wrong, or the template syntax has errors
**Debug:** Check `kubectl logs <pod> -c vault-agent` for the full error from the Vault Agent sidecar

### 4. Pod runs fine locally but fails after ArgoCD deploy
**Cause:** The deployment manifest does not have the `serviceAccountName` set, so it uses the `default` ServiceAccount which is not bound to any Vault role
**Fix:** Ensure `spec.template.spec.serviceAccountName: sample-app-sa` is in the deployment manifest

---

## Break It on Purpose

**1. Wrong ServiceAccount name in the deployment**
Deploy a pod with `serviceAccountName: wrong-sa` (a ServiceAccount that exists but is not bound to any Vault role).
Watch the pod: `kubectl get pod <pod> -w` — it stays in `Init:0/1`.
Read the init container logs: `kubectl logs <pod> -c vault-agent-init`
Observe the exact auth error: `Error authenticating: ... no role found for...`
Fix: set `serviceAccountName: sample-app-sa`.

**2. Wrong secret path (KV v2 mistake)**
In your Vault policy, set the path to `secret/sample-app/config` instead of `secret/data/sample-app/config`.
Deploy the pod. Init container authenticates successfully but fails when reading the secret: `1 error occurred: * permission denied`
This is the single most common Vault mistake — KV v2 uses `secret/data/...` in policies, but `secret/...` in the `vault kv get` CLI command. The two paths look the same but are different.
Fix: update the policy to `secret/data/sample-app/config`.

**3. Take Vault down during a deployment**
Stop the Vault pod: `kubectl -n vault scale deployment vault --replicas=0`
Trigger an ArgoCD sync that creates a new pod.
Watch the pod: it gets stuck in `Init:0/1`, the init container cannot connect to Vault.
`kubectl logs <pod> -c vault-agent-init` shows connection refused.
Observe: existing running pods are NOT affected (they already have the secrets written to the volume). Only new pod startups fail.
Fix: scale Vault back up: `kubectl -n vault scale deployment vault --replicas=1`
This teaches you the blast radius of Vault being down — it does not kill running pods, it only prevents new pod startups.

---

## Operational — Secret Rotation + Token Expiry

This is the point 5 from "what's missing for real learning." Covers what happens after the initial setup.

### Rotating a Secret Without Redeploying

Update the secret value in Vault:
```bash
kubectl exec -n vault vault-0 -- vault kv put secret/sample-app/config \
  db_password="newpassword456" \
  api_key="newkey789"
```

**What happens to running pods?**
- Static injection (init container only): the running pod's `/vault/secrets/config.properties` still has the OLD value. The new value only appears after the pod restarts.
- Agent sidecar with `vault.hashicorp.com/agent-inject: "true"` in sync mode: the sidecar watches Vault and rewrites the file when the secret changes. Your app must re-read the file periodically for this to work.

To force all pods to pick up the new secret immediately:
```bash
kubectl rollout restart deployment/sample-app
```
This triggers a rolling restart — old pods are terminated, new pods start and fetch the updated secret.

**Verify the rotation worked:**
```bash
kubectl exec -it <new-pod> -- cat /vault/secrets/config.properties
# Should show the new values
```

### Token TTL and Automatic Renewal

The Vault token issued to the pod has a TTL (you set `ttl=1h` in the role). After 1 hour, the token expires.

The Vault Agent sidecar handles this automatically — it renews the token before expiry (at 2/3 of TTL by default). You do not need to do anything for this.

To verify the sidecar is renewing:
```bash
kubectl logs <pod> -c vault-agent
# Look for lines like: "Successfully renewed token"
```

If you need a longer TTL for long-running pods:
```bash
vault write auth/kubernetes/role/sample-app \
  bound_service_account_names=sample-app-sa \
  bound_service_account_namespaces=default \
  policies=sample-app-policy \
  ttl=24h \
  max_ttl=48h
```

### What Happens When the Vault Pod Restarts

If Vault restarts (not just scale-down/up, but an actual restart), it starts **sealed** by default (not in dev mode). A sealed Vault rejects all requests.

In dev mode (what you set up): Vault auto-unseals on restart with the dev root token. In production: you must unseal Vault manually (or use auto-unseal with AWS KMS, GCP KMS, etc.) before pods can retrieve secrets.

To check if Vault is sealed:
```bash
kubectl exec -n vault vault-0 -- vault status
# Sealed: false → healthy
# Sealed: true  → must unseal before any secrets can be read
```

---

## Interview Questions

**Q: Why use Vault instead of Kubernetes Secrets for managing secrets?**
A: K8s Secrets are only base64-encoded and are stored unencrypted in etcd by default. Anyone with kubectl access can read them. They also end up in Git if you commit manifests. Vault provides encryption at rest, fine-grained access control via policies, audit logging of every secret access, and secret rotation without redeploying applications.

**Q: How does the Vault Agent Injector work?**
A: It is a mutating admission webhook that intercepts pod creation. When a pod has the `vault.hashicorp.com/agent-inject: true` annotation, the injector adds an init container (Vault Agent) and a sidecar to the pod spec. The init container authenticates with Vault using the pod's ServiceAccount JWT, fetches the secrets, and writes them to a shared volume at `/vault/secrets/`. The app reads secrets from that path.

**Q: What is the Kubernetes auth method in Vault?**
A: It is how Vault verifies that a pod is who it claims to be. Vault is configured to trust the K8s API server. When the Vault Agent init container presents the pod's ServiceAccount JWT token, Vault calls the K8s API to verify it's a real ServiceAccount. If verified, Vault checks which role that ServiceAccount is bound to and issues a short-lived Vault token for reading the allowed secrets.

**Q: A pod cannot read its injected secrets and the init container is in error. What do you check?**
A: Check `kubectl logs <pod> -c vault-agent-init`. Common causes: ServiceAccount name mismatch, wrong namespace in the Vault role binding, wrong secret path (KV v2 requires `secret/data/...` in policies), or Vault is unreachable due to a NetworkPolicy.

**Q: Where is Vault in the Jenkins pipeline?**
A: In a K8s-native setup, Vault is not a Jenkins pipeline stage. It operates at pod runtime — Vault Agent Injector injects secrets when the pod starts, after ArgoCD has deployed it. Jenkins uses its own Credential Store for CI/CD secrets (registry passwords, GitHub tokens). The separation is: Jenkins owns CI secrets, Vault owns application runtime secrets.
