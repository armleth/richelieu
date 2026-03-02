# richelieu_try

GitOps infrastructure for a K3s single-node cluster. ArgoCD manages itself and all applications declaratively from this repository.

## Stack

- **K3s** with Traefik ingress controller
- **ArgoCD v3.3.2** (self-managed via app-of-apps pattern)
- **HashiCorp Vault** (secrets backend)
- **External Secrets Operator** (syncs Vault secrets to Kubernetes)

## Repository structure

```
k8s/
  bootstrap/
    kustomization.yaml                      # Entry point — only thing applied manually
  apps/
    argocd/
      kustomization.yaml                    # Upstream install.yaml + patches + resources
      namespace.yaml
      ingress.yaml                          # Traefik IngressRoute for argocd.armleth.fr
      patches/
        patch-argocd-cm.yaml                # Admin account + external URL
        patch-argocd-cmd-params-cm.yaml     # server.insecure (TLS at Traefik)
      templates/
        argocd.yaml                         # Self-management Application CR
        vault.yaml                          # Vault Application CR (Helm)
        external-secrets.yaml               # ESO Application CR (Helm)
        external-secrets-config.yaml        # ClusterSecretStore Application CR
    external-secrets-config/
      cluster-secret-store.yaml             # ClusterSecretStore pointing to Vault
      vault-auth-sa.yaml                    # ServiceAccount for Vault K8s auth
```

## Bootstrap

### 1. Deploy ArgoCD

```bash
kubectl apply -k k8s/bootstrap/ --server-side
```

### 2. Wait for ArgoCD pods

```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

### 3. Get ArgoCD admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Login at `https://argocd.armleth.fr` with user `admin`.

> **Note:** The IngressRoute expects a TLS secret named `argocd-tls-secret` in the `argocd` namespace. You must provide this separately (or via an ExternalSecret from Vault once configured).

### 4. Initialize Vault

ArgoCD deploys Vault automatically. Wait for the pod, then init and unseal:

```bash
kubectl wait --for=condition=Ready=false pods -l app.kubernetes.io/name=vault -n vault --timeout=300s

kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 -key-threshold=1 -format=json > vault-init.json
```

**Save `vault-init.json` securely — it contains your unseal key and root token.**

### 5. Unseal Vault

```bash
UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-init.json)
kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"
```

> Vault must be unsealed every time the pod restarts.

### 6. Configure Vault

```bash
ROOT_TOKEN=$(jq -r '.root_token' vault-init.json)
kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN"

# Enable KV v2 secrets engine
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

# Enable and configure Kubernetes auth
kubectl exec -n vault vault-0 -- vault auth enable kubernetes
kubectl exec -n vault vault-0 -- sh -c 'vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443" \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'

# Create policy for External Secrets Operator
kubectl exec -n vault vault-0 -- sh -c \
  'echo "path \"secret/data/*\" { capabilities = [\"read\"] } path \"secret/metadata/*\" { capabilities = [\"read\", \"list\"] }" | vault policy write external-secrets -'

# Create role binding ESO ServiceAccount to the policy
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets-vault-auth \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h
```

### 7. Verify

```bash
kubectl get clustersecretstore vault-backend
```

Status should show `Valid`.

## Usage

To create a Kubernetes secret from Vault, write the secret to Vault then declare an `ExternalSecret`:

```bash
kubectl exec -n vault vault-0 -- vault kv put secret/my-app key=value
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secret
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-app-secret
  data:
    - secretKey: key
      remoteRef:
        key: secret/my-app
        property: key
```

Commit the `ExternalSecret` manifest to the repo and let ArgoCD sync it.

## Post-bootstrap

After the initial bootstrap, this repository is the single source of truth. All changes go through git — ArgoCD syncs automatically with pruning and self-healing enabled. The only manual operations are Vault init/unseal.
