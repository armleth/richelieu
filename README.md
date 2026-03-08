# richelieu

GitOps infrastructure for a K3s single-node cluster. ArgoCD manages itself and all applications declaratively from this repository.

**Before contributing or making changes, read [CONTRIBUTING.md](./CONTRIBUTING.md) for coding standards and guidelines.**

## Stack

- **K3s** with Traefik ingress controller
- **ArgoCD v3.3.2** (self-managed via app-of-apps pattern)
- **HashiCorp Vault** (secrets backend)
- **External Secrets Operator** (syncs Vault secrets to Kubernetes)
- **CloudNativePG** (PostgreSQL operator -- manages Keycloak's and Nextcloud's databases)
- **cert-manager** (automated TLS certificates via Let's Encrypt)
- **Keycloak** (centralized OIDC authentication for ArgoCD, Vault and Bbox)
- **Jellyfin** (media server)
- **Nextcloud** (file sync & sharing with Redis caching and PostgreSQL backend)
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
    bbox/                                   # Nginx reverse proxy to 192.168.1.254 (OIDC-protected)
    media/                                  # Jellyfin media server (jellyfin.armleth.fr)
    nextcloud/
      pvc.yaml                              # 100Gi PVC for Nextcloud data
      postgres.yaml                         # CloudNativePG Cluster + DB credentials (ExternalSecret)
      redis.yaml                            # Redis Deployment + Service for caching
      external-secret.yaml                  # Admin credentials (ExternalSecret from Vault)
      deployment.yaml                       # Nextcloud (nextcloud:latest)
      service.yaml                          # Nextcloud Service
      ingress.yaml                          # IngressRoute for nextcloud.armleth.fr
    keycloak/
      postgres.yaml                         # CloudNativePG Cluster + DB credentials (ExternalSecret)
      deployment.yaml                       # Keycloak 26.1 (quay.io/keycloak/keycloak)
      service.yaml                          # Keycloak Service
      admin-secret.yaml                     # Keycloak admin credentials (ExternalSecret from Vault)
      ingress.yaml                          # IngressRoute for auth.armleth.fr
      certificate.yaml                      # TLS certificate for auth.armleth.fr
      external-secret-argocd-oidc.yaml      # OIDC client secret for ArgoCD (from Vault)
terraform/
  vault/                                    # KV v2, K8s auth, ESO role, admin policy, OIDC auth
  keycloak/                                 # Realm, OIDC clients (argocd, vault, bbox), groups, master admin group
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

### 5. Configure Vault and store Keycloak secrets

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r '.root_token' vault-init.json)

cd terraform/vault
terraform init
terraform apply
cd ../..

# Generate and store Keycloak passwords in Vault
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv put secret/keycloak \
    admin-password="$(openssl rand -base64 24)" \
    db-password="$(openssl rand -base64 24)"
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
export KEYCLOAK_PASSWORD=$(kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv get -field=admin-password secret/keycloak)

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
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv put secret/argocd oidc-client-secret="$ARGOCD_CLIENT_SECRET"

VAULT_CLIENT_SECRET=$(cd terraform/keycloak && terraform output -raw vault_client_secret)
cd terraform/vault
terraform apply -var="vault_oidc_client_secret=$VAULT_CLIENT_SECRET"
cd ../..

BBOX_CLIENT_SECRET=$(cd terraform/keycloak && terraform output -raw bbox_client_secret)
COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv put secret/bbox \
    oidc-client-secret="$BBOX_CLIENT_SECRET" \
    cookie-secret="$COOKIE_SECRET"

# Store Nextcloud secrets (admin + database passwords)
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv put secret/nextcloud \
    admin-password="$(openssl rand -base64 24)" \
    db-password="$(openssl rand -base64 24)"
```

### 9. Create your Keycloak user

Log in to `https://auth.armleth.fr` with user `admin` and the password from step 5.

- In the **master** realm, create a user and add them to the `admin` group (grants full Keycloak admin privileges).
- Switch to the **infrastructure** realm, create the same user and add them to the `admins` group.

You can then log into ArgoCD and Vault via the **Keycloak** SSO option.

## Adding a TLS certificate

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

## Jellyfin hardware acceleration

Jellyfin is configured with Intel Quick Sync Video (QSV) hardware transcoding via `/dev/dri` passthrough from the host.

### Verify hardware acceleration

From the host, check that the DRI device is visible and usable inside the pod:

```bash
# Confirm /dev/dri is mounted
kubectl exec -n media deploy/jellyfin -- ls -la /dev/dri/

# Check VA-API driver loads correctly
kubectl exec -n media deploy/jellyfin -- \
  /usr/lib/jellyfin-ffmpeg/vainfo --display drm --device /dev/dri/renderD128
```

`vainfo` should report `Intel iHD driver` and list supported profiles.

### Jellyfin transcoding settings

In **Dashboard > Playback > Transcoding**:

- **Hardware acceleration**: Intel Quick Sync Video (QSV)
- **Enable hardware decoding for**:

| Codec | Enable |
|---|---|
| H264 | Yes |
| HEVC | Yes |
| MPEG2 | Yes |
| VC1 | Yes |
| VP8 | Yes |
| VP9 | Yes |
| HEVC 10bit | Yes |
| VP9 10bit | Yes |
| AV1 | No |
| HEVC RExt 8/10bit | No |
| HEVC RExt 12bit | No |

AV1 and HEVC RExt are not supported by the current Intel iGPU.

## Post-bootstrap

This repository is the single source of truth. All changes go through git -- ArgoCD syncs automatically with pruning and self-healing enabled.

Manual operations:
- **Vault unseal** (after pod restarts)
- **`terraform apply`** (when changing Vault or Keycloak configuration)
- **Keycloak user management** (via admin UI or Terraform)
