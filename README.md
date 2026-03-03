# richelieu_try

GitOps infrastructure for a K3s single-node cluster. ArgoCD manages itself and all applications declaratively from this repository.

## Stack

- **K3s** with Traefik ingress controller
- **ArgoCD v3.3.2** (self-managed via app-of-apps pattern)
- **HashiCorp Vault** (secrets backend)
- **External Secrets Operator** (syncs Vault secrets to Kubernetes)
- **cert-manager** (automated TLS certificates via Let's Encrypt)
- **Keycloak** (centralized OIDC authentication for ArgoCD and Vault)
- **Terraform** (Vault and Keycloak configuration as code)

## Repository structure

```
k8s/
  bootstrap/
    kustomization.yaml                      # Entry point -- only thing applied manually
  apps/
    argocd/
      kustomization.yaml                    # Upstream install.yaml + patches + resources
      namespace.yaml
      ingress.yaml                          # IngressRoute for argocd.armleth.fr
      patches/
        patch-argocd-cm.yaml                # Admin account + URL + OIDC config
        patch-argocd-cmd-params-cm.yaml     # server.insecure (TLS at Traefik)
        patch-argocd-rbac-cm.yaml           # RBAC: Keycloak admins -> role:admin
      templates/                            # App-of-apps Application CRs
    vault-config/
      ingress.yaml                          # IngressRoute for vault.armleth.fr
    external-secrets-config/
      cluster-secret-store.yaml             # ClusterSecretStore pointing to Vault
      vault-auth-sa.yaml                    # ServiceAccount for Vault K8s auth
    cert-manager-config/
      cluster-issuer.yaml                   # Let's Encrypt ClusterIssuer (HTTP-01)
      certificates/                         # TLS certificates for all services
    bbox/                                   # Nginx reverse proxy to 192.168.1.254
    keycloak/
      postgres.yaml                         # PostgreSQL 16 StatefulSet + Service
      deployment.yaml                       # Keycloak 26.1 (quay.io/keycloak/keycloak)
      service.yaml                          # Keycloak Service
      admin-secret.yaml                     # Keycloak admin credentials
      ingress.yaml                          # IngressRoute for auth.armleth.fr
      certificate.yaml                      # TLS certificate for auth.armleth.fr
      external-secret-argocd-oidc.yaml      # OIDC client secret for ArgoCD (from Vault)
terraform/
  vault/                                    # KV v2, K8s auth, ESO role, OIDC auth
  keycloak/                                 # Realm, OIDC clients, groups, token mappers
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

### 4. Initialize and unseal Vault

```bash
kubectl wait --for=condition=Ready=false pods -l app.kubernetes.io/name=vault -n vault --timeout=300s

kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 -key-threshold=1 -format=json > vault-init.json

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-init.json)
kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"
```

**Save `vault-init.json` securely.** Vault must be unsealed after every pod restart.

### 5. Configure Vault with Terraform

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' vault-init.json)

cd terraform/vault
terraform init
terraform apply
cd ../..
```

### 6. Verify ESO

```bash
kubectl get clustersecretstore vault-backend
```

Status should show `Valid`.

### 7. Configure Keycloak

```bash
kubectl wait --for=condition=Ready pods -l app=keycloak -n keycloak --timeout=600s

kubectl port-forward -n keycloak svc/keycloak 8080:80 &

export KEYCLOAK_URL=http://localhost:8080
export KEYCLOAK_USER=admin
export KEYCLOAK_PASSWORD=$(kubectl get secret -n keycloak keycloak-admin-secret -o jsonpath='{.data.password}' | base64 -d)

cd terraform/keycloak
terraform init
terraform apply
cd ../..
```

### 8. Store OIDC secrets and enable Vault OIDC

Ensure port-forwards from steps 5 and 7 are still running.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' vault-init.json)

ARGOCD_CLIENT_SECRET=$(cd terraform/keycloak && terraform output -raw argocd_client_secret)
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv put secret/argocd oidc-client-secret="$ARGOCD_CLIENT_SECRET"
cd ../..

VAULT_CLIENT_SECRET=$(cd terraform/keycloak && terraform output -raw vault_client_secret)
cd terraform/vault
terraform apply -var="vault_oidc_client_secret=$VAULT_CLIENT_SECRET"
cd ../..
```

### 9. Create your Keycloak user

Log in to `https://auth.armleth.fr`, switch to the `infrastructure` realm, create a user and add them to the `admins` group.

## Adding a TLS certificate

To add a certificate for a new subdomain:

1. Create `k8s/apps/cert-manager-config/certificates/<app>.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <app>-tls
  namespace: <app-namespace>
spec:
  secretName: <app>-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - <app>.armleth.fr
```

2. Add it to `k8s/apps/cert-manager-config/kustomization.yaml`.
3. Reference `secretName: <app>-tls-secret` in your IngressRoute's `tls` block.
4. Commit and push.

## Post-bootstrap

This repository is the single source of truth. All changes go through git -- ArgoCD syncs automatically with pruning and self-healing enabled.

Manual operations:
- **Vault unseal** (after pod restarts)
- **`terraform apply`** (when changing Vault or Keycloak configuration)
- **Keycloak user management** (via admin UI or Terraform)
