# richelieu_try

GitOps infrastructure for a K3s single-node cluster. ArgoCD manages itself and all applications declaratively from this repository.

## Stack

- **K3s** with Traefik ingress controller
- **ArgoCD v3.3.2** (self-managed via app-of-apps pattern)
- **HashiCorp Vault** (secrets backend)
- **External Secrets Operator** (syncs Vault secrets to Kubernetes)
- **Terraform** (Vault configuration as code)

## Repository structure

```
k8s/
  bootstrap/
    kustomization.yaml                      # Entry point -- only thing applied manually
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
        vault-config.yaml                   # Vault IngressRoute Application CR
        external-secrets.yaml               # ESO Application CR (Helm)
        external-secrets-config.yaml        # ClusterSecretStore Application CR
    vault-config/
      ingress.yaml                          # Traefik IngressRoute for vault.armleth.fr
    external-secrets-config/
      cluster-secret-store.yaml             # ClusterSecretStore pointing to Vault
      vault-auth-sa.yaml                    # ServiceAccount for Vault K8s auth
terraform/
  vault/
    main.tf                                 # Vault provider
    versions.tf                             # Required providers
    secrets.tf                              # KV v2 engine
    auth.tf                                 # Kubernetes auth backend
    policies.tf                             # ESO read-only policy
    roles.tf                                # ESO K8s auth role
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

> **Note:** The IngressRoutes expect TLS secrets (`argocd-tls-secret` in `argocd`, `vault-tls-secret` in `vault`). Provide these separately or via ExternalSecrets once Vault is configured.

### 4. Initialize and unseal Vault

ArgoCD deploys Vault automatically. Wait for the pod, then init and unseal:

```bash
kubectl wait --for=condition=Ready=false pods -l app.kubernetes.io/name=vault -n vault --timeout=300s

kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 -key-threshold=1 -format=json > vault-init.json

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-init.json)
kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"
```

**Save `vault-init.json` securely -- it contains your unseal key and root token.**

> Vault must be unsealed every time the pod restarts.

### 5. Configure Vault with Terraform

Port-forward Vault and apply the Terraform configuration:

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' vault-init.json)

cd terraform/vault
terraform init
terraform apply
```

This declaratively configures:
- KV v2 secrets engine at `secret/`
- Kubernetes auth backend
- `external-secrets` policy (read-only access to `secret/*`)
- `external-secrets` role (bound to ESO ServiceAccount)

### 6. Verify

```bash
kubectl get clustersecretstore vault-backend
```

Status should show `Valid`.

## Usage

Write secrets via the Vault UI at `https://vault.armleth.fr` or CLI:

```bash
kubectl exec -n vault vault-0 -- vault kv put secret/my-app key=value
```

Then declare an `ExternalSecret` in the repo:

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

Commit and push -- ArgoCD syncs it automatically.

## Post-bootstrap

This repository is the single source of truth. All changes go through git -- ArgoCD syncs automatically with pruning and self-healing enabled.

The only manual operations are:
- **Vault init** (one-time)
- **Vault unseal** (after pod restarts)
- **`terraform apply`** (when changing Vault configuration)
