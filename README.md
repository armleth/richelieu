# Richelieu

GitOps infrastructure for a K3s single-node cluster. ArgoCD manages itself and all applications declaratively from this repository.

**Before contributing or making changes, read [CONTRIBUTING.md](./CONTRIBUTING.md) for coding standards and guidelines.**

## Stack

- **K3s** with Traefik ingress controller (cross-namespace middleware + cluster-wide HTTP→HTTPS 301 redirect enabled via HelmChartConfig)
- **ArgoCD v3.3.2** (self-managed via app-of-apps pattern)
- **HashiCorp Vault** (secrets backend)
- **External Secrets Operator** (syncs Vault secrets to Kubernetes)
- **CloudNativePG** (PostgreSQL operator -- manages Authentik's, Nextcloud's, and Lathibandolaise's databases)
- **cert-manager** (automated TLS certificates via Let's Encrypt)
- **Authentik** (centralized OIDC + proxy authentication for ArgoCD, Vault, Homepage, Bbox, Code Server, Lathibandolaise, DbGate, Actual Budget, and media stack)
- **Media stack** (Jellyfin, Radarr, Sonarr, Prowlarr, FlareSolverr, qBittorrent, Flood)
- **Nextcloud** (file sync & sharing with Redis caching and PostgreSQL backend)
- **Homepage** (OIDC-protected dashboard with per-service resource monitoring -- home.armleth.fr)
- **Code Server** (OIDC-protected VS Code in the browser -- dev.armleth.fr)
- **Lathibandolaise** (test + prod deployments with CNPG Postgres, ForwardAuth via Authentik -- test.lathibandolaise.dev.armleth.fr / prod.lathibandolaise.dev.armleth.fr)
- **DbGate** (OIDC-protected database browser for the Lathibandolaise PostgreSQL cluster -- db.lathibandolaise.dev.armleth.fr)
- **Actual Budget** (self-hosted personal finance manager with native OIDC against Authentik, admin-only -- finances.armleth.fr)
- **Monitoring** (kube-prometheus-stack + prometheus-blackbox-exporter; Grafana with native OIDC against Authentik, admin-only -- metrics.armleth.fr)
- **Terraform** (Vault and Authentik configuration as code)

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
      external-secret-oidc.yaml             # OIDC client secret for Authentik (from Vault)
      patches/
        patch-argocd-cm.yaml                # Admin account + URL + OIDC config (Authentik)
        patch-argocd-cmd-params-cm.yaml     # server.insecure (TLS at Traefik)
        patch-argocd-rbac-cm.yaml           # RBAC: Authentik admin -> role:admin
      templates/                            # App-of-apps Application CRs
    vault-config/
      ingress.yaml                          # IngressRoute for vault.armleth.fr
    external-secrets-config/
      cluster-secret-store.yaml             # ClusterSecretStore pointing to Vault
      vault-auth-sa.yaml                    # ServiceAccount for Vault K8s auth
    cert-manager-config/
      cluster-issuer.yaml                   # Let's Encrypt ClusterIssuer (HTTP-01)
      certificates/                         # TLS certificates for all services
    authentik/                              # Authentik identity provider (auth.armleth.fr)
      postgres.yaml                         # CloudNativePG Cluster + DB credentials (ExternalSecret)
      external-secret.yaml                  # Authentik core secrets (ExternalSecret from Vault)
      deployment-server.yaml                # Authentik server (ghcr.io/goauthentik/server)
      deployment-worker.yaml                # Authentik background worker
      service.yaml                          # Authentik Service
      ingress.yaml                          # IngressRoute for auth.armleth.fr
      middleware.yaml                       # Traefik ForwardAuth middleware
    bbox/                                   # Nginx reverse proxy to 192.168.1.254 (ForwardAuth via Authentik)
    media/                                  # Media stack (all services in namespace: media)
      downloads-pvc.yaml                    # Shared 100Gi PVC for torrent downloads
      jellyfin/                             # Media server (media.armleth.fr)
      radarr/                               # Movie manager (movies.media.armleth.fr)
      sonarr/                               # TV show manager (series.media.armleth.fr)
      prowlarr/                             # Indexer manager (trackers.media.armleth.fr)
      flaresolverr/                         # Cloudflare bypass (internal only)
      qbittorrent/                          # Torrent client (torrents.media.armleth.fr)
      flood/                                # Torrent UI (downloads.media.armleth.fr)
    homepage/                               # Dashboard (home.armleth.fr, OIDC-protected)
      rbac.yaml                             # ServiceAccount + ClusterRole + ClusterRoleBinding
      configmap.yaml                        # Homepage YAML configuration files
      deployment.yaml                       # Homepage (ghcr.io/gethomepage/homepage)
      service.yaml                          # Homepage Service
      ingress.yaml                          # IngressRoute for home.armleth.fr (ForwardAuth via Authentik)
    code-server/                            # VS Code in the browser (dev.armleth.fr, OIDC-protected)
      external-secret.yaml                  # git PAT secret (ExternalSecret from Vault)
      deployment.yaml                       # code-server (codercom/code-server)
      service.yaml                          # code-server Service
      ingress.yaml                          # IngressRoute for dev.armleth.fr (ForwardAuth via Authentik)
    nextcloud/
      pvc.yaml                              # 100Gi PVC for Nextcloud data
      postgres.yaml                         # CloudNativePG Cluster + DB credentials (ExternalSecret)
      redis.yaml                            # Redis Deployment + Service for caching
      external-secret.yaml                  # Admin credentials (ExternalSecret from Vault)
      deployment.yaml                       # Nextcloud (nextcloud:latest)
      service.yaml                          # Nextcloud Service
      ingress.yaml                          # IngressRoute for nextcloud.armleth.fr
    lathibandolaise/                        # Test + prod app (ForwardAuth via Authentik)
      postgres.yaml                         # CloudNativePG Cluster + DB credentials (ExternalSecret)
      external-secret.yaml                  # App secret (DATABASE_URL) + GHCR pull secret + git PAT secret
      deployment-test.yaml                  # Test env (php:8.3-cli-alpine, hostPath /data/lathibandolaise)
      deployment-prod.yaml                  # Prod env (php:8.3-cli-alpine, in-cluster clone via git PAT)
      service-test.yaml                     # Test Service (port 3000)
      service-prod.yaml                     # Prod Service (port 3000)
      ingress.yaml                          # IngressRoutes for test/prod subdomains
    dbgate/                                 # DbGate database browser (db.lathibandolaise.dev.armleth.fr, OIDC-protected)
      deployment.yaml                       # DbGate (dbgate/dbgate, connects to lathibandolaise-pg-rw)
      external-secret.yaml                  # DB connection secret (reuses secret/lathibandolaise)
      service.yaml                          # DbGate Service (port 3000)
      ingress.yaml                          # IngressRoute for db.lathibandolaise.dev.armleth.fr (ForwardAuth via Authentik)
    actual-budget/                          # Actual Budget personal finance manager (finances.armleth.fr, native OIDC via Authentik)
      external-secret.yaml                  # OIDC client secret (ExternalSecret from Vault: secret/actual-budget:oidc-client-secret)
      pvc.yaml                              # 10Gi PVC for SQLite DB + budget files (/data)
      deployment.yaml                       # Actual Budget (actualbudget/actual-server:latest, port 5006, ACTUAL_LOGIN_METHOD=openid)
      service.yaml                          # Actual Budget Service (port 5006)
      ingress.yaml                          # IngressRoute for finances.armleth.fr (plain HTTPS, no ForwardAuth)
    monitoring-config/                      # Local CRs for the monitoring stack (namespace: monitoring)
      namespace.yaml                        # monitoring Namespace
      external-secret.yaml                  # Grafana OIDC client secret (ExternalSecret from Vault: secret/grafana:oidc-client-secret)
      ingressroute-grafana.yaml             # IngressRoute for metrics.armleth.fr (Grafana, native OIDC inside the app)
      servicemonitor-argocd.yaml            # ServiceMonitor for ArgoCD metrics services
      probes.yaml                           # Three blackbox Probe CRs (open / protected / media)
terraform/
  vault/                                    # KV v2, K8s auth, ESO role, admin policy, OIDC auth
  authentik/                                # Groups, OIDC providers, proxy providers (incl. Lathibandolaise), applications, policy bindings
```

## Bootstrap

Everything in this section runs from your **workstation**, not on the K3s node. The only things that happen on the node are two host-level directory operations (step 9), which you either run over SSH automatically or execute manually.

### 0. Workstation prerequisites

Install locally: `kubectl`, `terraform`, `jq`, `openssl`, `git`.

Fetch the K3s kubeconfig into the default location `~/.kube/config` and point it at the server's real address:

```bash
mkdir -p ~/.kube
ssh armleth@<server> sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
chmod 600 ~/.kube/config
sed -i "s|https://127.0.0.1:6443|https://<server>:6443|" ~/.kube/config
kubectl get nodes   # sanity check
```

(If you already manage other clusters in `~/.kube/config`, merge instead of overwriting: `KUBECONFIG=~/.kube/config:./new.yaml kubectl config view --flatten > ~/.kube/merged && mv ~/.kube/merged ~/.kube/config`.)

Optional but recommended for step 9 (lets the script run host-level commands over SSH instead of pausing for manual action):

```bash
export RICHELIEU_SSH_HOST=armleth@<server>
```

Then run `./setup.sh` to execute every step below automatically, or follow them manually. `vault-init.json` (written in step 4) is saved at the repo root on your workstation and is already in `.gitignore` -- move it to a password manager or encrypted backup once bootstrap is done.

### 1. Deploy ArgoCD

```bash
kubectl apply -k k8s/bootstrap/ --server-side --force-conflicts \
  --field-manager=argocd-controller
```

`--field-manager=argocd-controller` is important: it writes every field under the same SSA manager ArgoCD itself uses after bootstrap. Without it, the default `kubectl` manager ends up permanently co-owning the same fields as `argocd-controller` on the app-of-apps Application CRs. That co-ownership causes SSA conflicts on later syncs, and ArgoCD's self-heal retry injects `syncStrategy.hook.force: true` into the sync operation -- which maps to kubectl's `--force` flag and is rejected with `error validating options: --force cannot be used with --server-side`. The parent `argocd` app then gets stuck `OutOfSync` in an infinite retry loop. This mainly affects child Applications with `argocd.argoproj.io/sync-wave` annotations (`cert-manager`, `cert-manager-config`, `authentik`), because v3.3.2 routes later-wave applies through a kubectl-subprocess path that actually emits `--force`.

Expect transient errors during the first minutes that go away on retry:

- `no matches for kind "Application"` / `no matches for kind "ExternalSecret"` -- CRDs are being created in the same pass as the CRs that use them; the API discovery cache is stale until the next apply. The `ExternalSecret` CRD is installed only once ArgoCD has synced the `external-secrets` Application (1-3 min).
- `Apply failed with N conflicts: conflict with "argocd-controller"` -- ArgoCD starts reconciling itself mid-bootstrap and grabs field ownership. `--force-conflicts` tells the API server to hand ownership back to our apply (git is source of truth). Because we apply under the same field manager (`argocd-controller`), ownership stays consistent afterwards.
- `failed calling webhook ... no endpoints available for service "external-secrets-webhook"` -- the admission webhook pods haven't finished rolling out.

Run the command in a loop until it exits cleanly:

```bash
until kubectl apply -k k8s/bootstrap/ --server-side --force-conflicts \
    --field-manager=argocd-controller; do sleep 10; done
```

`setup.sh` does this automatically (with a 10-minute timeout and an error-allowlist so genuine failures surface immediately).

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

`vault-init.json` is written to your workstation, **not** the node -- keep it safe (password manager or encrypted backup) and out of git. Vault must be unsealed after every pod restart.

### 5. Configure Vault

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

### 7. Store Authentik and Nextcloud secrets

```bash
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" sh -c '
  vault kv put secret/authentik \
    admin-password="$(openssl rand -base64 24)" \
    secret-key="$(openssl rand -base64 60 | tr -d '\\n')" \
    db-password="$(openssl rand -base64 24)"
  vault kv put secret/nextcloud \
    admin-password="$(openssl rand -base64 24)" \
    db-password="$(openssl rand -base64 24)"
  vault kv put secret/lathibandolaise \
    db-password="$(openssl rand -base64 24)" \
    ghcr-pat="<base64-encoded armleth:github-pat>" \
    git-pat="<github-pat>"
'
```

### 8. Configure Traefik

Two cluster-wide Traefik settings are applied together via a single `HelmChartConfig`:

1. **Cross-namespace middleware.** Authentik's ForwardAuth middleware lives in the `authentik` namespace but is referenced by IngressRoutes in other namespaces — Traefik blocks this by default.
2. **HTTP→HTTPS redirect.** An entrypoint-level 301 redirect sends every request arriving on port 80 to its HTTPS equivalent (same host, path, query). This is safe with Let's Encrypt's HTTP-01 challenge because the ACME client follows 3xx redirects and accepts any certificate on the redirect target.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    providers:
      kubernetesCRD:
        allowCrossNamespace: true
    ports:
      websecure:
        port: 443
        exposedPort: 443
    additionalArguments:
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
EOF
```

K3s will automatically redeploy Traefik with the new settings. Wait for it:

```bash
kubectl rollout status deployment/traefik -n kube-system --timeout=120s
```

Verify the redirect with any host, e.g.:

```bash
curl -sI http://home.armleth.fr | head -n 2
# HTTP/1.1 308 Permanent Redirect
# Location: https://home.armleth.fr/
```

Note: the `ports.websecure.port: 443` override is required because the K3s Traefik chart defaults to `:8443` internally (host port 443 → container 8443 via the Service). Traefik's entrypoint redirection uses the target entrypoint's port verbatim in the `Location` header, so without the override every redirect would land on `https://<host>:8443/`. Setting the entrypoint to `:443` makes the port match HTTPS's default and Traefik omits it from the URL.

### 9. Configure Authentik

```bash
kubectl wait --for=condition=Ready pods -l app=authentik-server -n authentik --timeout=600s

# Generate a recovery link to access the admin UI
kubectl exec -n authentik deployment/authentik-worker -- ak create_recovery_key 10 akadmin

# Open the recovery link in your browser, then create an API token:
# Settings > Tokens and App passwords > Create (intent: API)

kubectl port-forward -n authentik svc/authentik-server 9000:80 &
export AUTHENTIK_URL=http://localhost:9000
export AUTHENTIK_TOKEN=<api-token>

cd terraform/authentik
terraform init
terraform apply

# Store OIDC client secrets in Vault
ARGOCD_CLIENT_SECRET=$(terraform output -raw argocd_client_secret)
VAULT_CLIENT_SECRET=$(terraform output -raw vault_client_secret)
ACTUAL_BUDGET_CLIENT_SECRET=$(terraform output -raw actual_budget_client_secret)
GRAFANA_CLIENT_SECRET=$(terraform output -raw grafana_client_secret)
cd ../..

kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv put secret/argocd oidc-client-secret="$ARGOCD_CLIENT_SECRET"

kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  ACTUAL_BUDGET_CLIENT_SECRET="$ACTUAL_BUDGET_CLIENT_SECRET" \
  sh -c 'vault kv put secret/actual-budget oidc-client-secret="$ACTUAL_BUDGET_CLIENT_SECRET"'

kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  GRAFANA_CLIENT_SECRET="$GRAFANA_CLIENT_SECRET" \
  sh -c 'vault kv put secret/grafana oidc-client-secret="$GRAFANA_CLIENT_SECRET"'

# Verify the secrets were stored correctly
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv get -field=oidc-client-secret secret/argocd
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv get -field=oidc-client-secret secret/actual-budget
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv get -field=oidc-client-secret secret/grafana

cd terraform/vault
terraform apply -var="vault_oidc_client_secret=$VAULT_CLIENT_SECRET"
cd ../..

# Restart ArgoCD server to pick up the new OIDC secret
kubectl rollout restart deployment argocd-server -n argocd
```

### 10. Create your Authentik user

Log in to `https://auth.armleth.fr` using a recovery link (see step 9).

- Go to **Directory > Users** and create your user
- Go to **Directory > Groups** and assign the user to the groups they need:
  - `admin` -- full access (all services)
  - `bbox` -- Bbox access for non-admins
  - `dev` -- Code Server, Lathibandolaise (test/prod), DbGate
  - (Actual Budget is admin-only; no dedicated group)
  - `media` -- Radarr, Sonarr, Prowlarr, qBittorrent, Flood

  Groups are managed declaratively in `terraform/authentik/groups.tf`; only user creation and assignment is done via the UI.

You can then log into ArgoCD, Vault, Bbox, Homepage, Code Server, Lathibandolaise, DbGate, Actual Budget, Grafana, and the media stack via the **Authentik** SSO option.

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

## Media stack

All media services run in the `media` namespace, managed by a single ArgoCD Application.

| Service | URL | Purpose |
|---|---|---|
| Jellyfin | `media.armleth.fr` | Media streaming frontend |
| Radarr | `movies.media.armleth.fr` | Movie search & organization |
| Sonarr | `series.media.armleth.fr` | TV show search & organization |
| Prowlarr | `trackers.media.armleth.fr` | Indexer manager (syncs to Radarr/Sonarr) |
| FlareSolverr | internal only | Cloudflare bypass for Prowlarr |
| qBittorrent | `torrents.media.armleth.fr` | Torrent download client |
| Flood | `downloads.media.armleth.fr` | Modern torrent UI for qBittorrent |

### DNS records

All media subdomains must have A/CNAME records pointing to the server:

```
movies.media.armleth.fr
series.media.armleth.fr
trackers.media.armleth.fr
torrents.media.armleth.fr
downloads.media.armleth.fr
```

### Host setup

Create the media directories on the K3s node and set ownership to UID/GID 1000 (used by linuxserver.io containers). From your workstation:

```bash
ssh armleth@<server> '
  sudo mkdir -p /data/media/movies /data/media/tv
  sudo chown 1000:1000 /data/media/movies /data/media/tv
'
```

(`setup.sh` does this automatically when `RICHELIEU_SSH_HOST` is exported.)

Alternatively, create the directories from within a running pod (useful if SSH isn't available):

```bash
kubectl exec -n media deploy/radarr -- mkdir -p /media/movies /media/tv
kubectl exec -n media deploy/radarr -- chown 1000:1000 /media/movies /media/tv
```

### DNS Configuration

Prowlarr requires DNS resolution for external torrent indexer sites (1337x.to, thepiratebay.org, etc.). Some ISP DNS servers block these domains.

CoreDNS must be configured to use public DNS servers that don't block torrent sites:

```bash
kubectl patch configmap coredns -n kube-system --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    hosts /etc/coredns/NodeHosts {\n      ttl 60\n      reload 15s\n      fallthrough\n    }\n    prometheus :9153\n    forward . 1.1.1.1 8.8.8.8\n    cache 30\n    loop\n    reload\n    loadbalance\n    import /etc/coredns/custom/*.override\n}\nimport /etc/coredns/custom/*.server\n"}}'

kubectl rollout restart deployment coredns -n kube-system
```

This configures CoreDNS to forward queries to Cloudflare (1.1.1.1) and Google DNS (8.8.8.8).

Verify DNS resolution works:

```bash
kubectl exec -n media deploy/prowlarr -- nslookup 1337x.to
```

### Shared volumes

- **`media-downloads`** (100Gi PVC): shared by qBittorrent, Radarr, Sonarr, Flood, and Jellyfin at `/downloads`
- **`/data/media`** (hostPath): shared by Jellyfin, Radarr, and Sonarr at `/media` -- organized media library

### Service wiring (post-deploy)

After pods are running, configure the services through their web UIs:

1. **Prowlarr**:
   - Settings > Indexers > Add FlareSolverr tag with URL `http://flaresolverr-service:8191`
   - Indexers > Add torrent indexers
   - Settings > Apps > Add Radarr and Sonarr (indexers auto-sync)

2. **Radarr**:
   - Indexers are auto-synced from Prowlarr
   - Settings > Download Clients > Add qBittorrent: host `qbittorrent-service`, port `8080`
   - Settings > Media Management > Root Folders: `/media/movies`

3. **Sonarr**:
   - Indexers are auto-synced from Prowlarr
   - Same download client (qBittorrent at `qbittorrent-service:8080`)
   - Root Folder: `/media/tv`

4. **qBittorrent**:
   - Tools > Options > Web UI > check "Bypass authentication for clients in whitelisted IP subnets" and add `0.0.0.0/0` (auth is handled by Authentik)
   - Settings > BitTorrent > Share Ratio Limiting
   - If you want to disable seeding, check "When ratio reaches" and set to `0`
   - Set action to "Stop torrent"
   - Click "Save" at the bottom

5. **Flood**: No setup needed -- built-in auth is disabled via `--noauth` and qBittorrent connection is pre-configured via `--qburl` (Authentik handles authentication).

6. **Jellyfin**: Add library paths for `/media/movies` and `/media/tv`.

### Data flow

```
User adds movie/show in Radarr/Sonarr
  -> Radarr/Sonarr searches via Prowlarr (which uses FlareSolverr for Cloudflare-protected sites)
  -> Radarr/Sonarr sends torrent to qBittorrent
  -> qBittorrent downloads to /downloads (shared PVC)
  -> Radarr/Sonarr hard-links completed files to /media/movies or /media/tv
  -> Jellyfin serves the media
```

## Homepage

Homepage is a lightweight dashboard at `https://home.armleth.fr` showing all services grouped by category (Media, Infrastructure). It uses the Kubernetes metrics API via an in-cluster ServiceAccount to display per-pod CPU and memory usage for each service, along with cluster-wide resource totals and host disk usage.

**Authentication**: Homepage is protected with Authentik ForwardAuth. Any authenticated Authentik user can access the dashboard.

**Prerequisite**: `metrics-server` must be running in the cluster (pre-installed with K3s). Verify with `kubectl top nodes`.

## Code Server

Code Server provides VS Code in the browser at `https://dev.armleth.fr`. It runs with `--auth=none` since all authentication is handled by Authentik ForwardAuth. Users in the `admin` or `dev` group can access the editor. A 5Gi PVC persists the `/home/coder` directory (workspace, extensions, settings) across restarts. The `/data/lathibandolaise` hostPath is mounted at `/home/coder/lathibandolaise` for shared access with the test deployment; it is populated in-cluster by code-server's `git-bootstrap` init container on first boot using the Vault-stored `secret/lathibandolaise:git-pat`. The token is written to `~/.git-credentials` on the PVC (mode 0600) with `credential.helper=store`, so `git pull`/`commit`/`push` from the integrated terminal and the VS Code Source Control panel authenticate transparently. The token is never embedded in `git remote -v`.

## Lathibandolaise

Lathibandolaise runs in a single namespace with test and prod deployments, both protected by Authentik ForwardAuth (admin + dev groups).

| Environment | URL | Image | Source |
|---|---|---|---|
| Test | `test.lathibandolaise.dev.armleth.fr` | `php:8.3-cli-alpine` (with `pdo_pgsql`) | hostPath `/data/lathibandolaise` (shared with code-server) |
| Prod | `prod.lathibandolaise.dev.armleth.fr` | `php:8.3-cli-alpine` (with `pdo_pgsql`) | in-cluster clone of `main`, re-cloned on every pod start |

**Deploying to prod** = `kubectl -n lathibandolaise rollout restart deploy lathibandolaise-prod`. The `git-clone` init container wipes the emptyDir, does a `git clone --depth 1 --branch main` using the Vault-stored `git-pat`, then scrubs the token out of `.git/config` so the running container has no credentials at rest. Editing files in code-server does not affect prod until the changes are committed, pushed, and the prod deployment is restarted.

### Setup

1. Store secrets in Vault:

```bash
vault kv put secret/lathibandolaise \
  db-password="$(openssl rand -base64 24)" \
  ghcr-pat="$(echo -n 'armleth:<github-pat>' | base64)" \
  git-pat="<github-pat>"
```

2. Both test and prod working trees are cloned automatically once `secret/lathibandolaise:git-pat` is in Vault: code-server's init container populates the shared `/data/lathibandolaise` hostPath (seen by `lathibandolaise-test`), and the prod deployment's init container clones into its own emptyDir on every pod start.

3. DNS: Add A/CNAME records for `test.lathibandolaise.dev.armleth.fr` and `prod.lathibandolaise.dev.armleth.fr`.

## DbGate

DbGate is a web-based database browser at `https://db.lathibandolaise.dev.armleth.fr`, deployed in the `lathibandolaise` namespace. It connects to the `lathibandolaise-pg-rw` CNPG service and reuses `secret/lathibandolaise:db-password` (surfaced via the `dbgate-app-secret` ExternalSecret). Authentication is handled by Authentik ForwardAuth -- users in the `admin` or `dev` group can access it.

## Actual Budget

Actual Budget is a self-hosted personal finance manager at `https://finances.armleth.fr`, deployed in the `actual-budget` namespace. It uses its bundled SQLite database (no CNPG cluster), persisted on a 10Gi RWO PVC mounted at `/data`. Authentication uses Actual Budget's native OpenID Connect integration against Authentik (`ACTUAL_LOGIN_METHOD=openid`); only users in the `admin` group are allowed by the Authentik application policy. The OIDC client secret is stored in Vault at `secret/actual-budget:oidc-client-secret` and surfaced to the pod via the `actual-budget-oidc` ExternalSecret. The Authentik application's redirect URI is `https://finances.armleth.fr/openid/callback`.

## Monitoring

A lightweight observability stack runs in the `monitoring` namespace, deployed as three Helm-based ArgoCD Applications (`kube-prometheus-stack`, `prometheus-blackbox-exporter`, `scaphandre`) plus a sibling Kustomize app (`monitoring-config`) that holds the local CRs (Namespace, ExternalSecret, IngressRoute, ServiceMonitor, Probes).

| Component | Purpose |
|---|---|
| Prometheus | Metrics database, 7d retention, 5Gi PVC, internal-only (no ingress) |
| Grafana | Visualization at `metrics.armleth.fr`, 1Gi PVC, native OIDC against Authentik (admin-only) |
| node-exporter | Host CPU / memory / disk / network metrics |
| kube-state-metrics | Kubernetes object state metrics |
| prometheus-blackbox-exporter | HTTP uptime probing of public services |
| scaphandre | Host / per-process electrical power consumption (Intel/AMD RAPL) for energy-cost tracking |

Alertmanager and the K3s-incompatible scrape targets (`kubeControllerManager`, `kubeScheduler`, `kubeProxy`, `kubeEtcd`) are disabled.

**OIDC bootstrap** (covered by `setup.sh` step 10, but if redoing manually):

```bash
GRAFANA_CLIENT_SECRET=$(cd terraform/authentik && terraform output -raw grafana_client_secret)

kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  GRAFANA_CLIENT_SECRET="$GRAFANA_CLIENT_SECRET" \
  sh -c 'vault kv put secret/grafana oidc-client-secret="$GRAFANA_CLIENT_SECRET"'
```

**Authentication.** Grafana uses the OIDC `generic_oauth` provider (not Traefik ForwardAuth -- the IngressRoute therefore has no `authentik-forward-auth` middleware). The Authentik application is bound to the `admin` group; the `role_attribute_path` JMESPath expression `contains(groups[*], 'admin') && 'Admin' || 'Viewer'` maps `admin`-group members to Grafana's `Admin` role and any other authenticated user to `Viewer`.

**Prometheus access.** Prometheus has no ingress. To reach the UI:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# then open http://localhost:9090/targets
```

**Recommended dashboards** (Grafana > Dashboards > Import):

- Node Exporter Full -- ID `1860`
- Kubernetes / Compute Resources / Cluster (kube-state-metrics) -- bundled
- ArgoCD -- ID `14584`
- Blackbox Exporter -- ID `7587`
- **Energy / Power consumption** -- bundled in this repo at `k8s/apps/monitoring-config/dashboard-energy.yaml`, auto-loaded by the Grafana sidecar (ConfigMap labeled `grafana_dashboard: "1"`). Replaces the upstream community dashboard `13845`, which depends on `exe=` exact-match labels (`exe="prometheus"`, `exe=~"etcd|kube-apiserver|..."`) that never match on NixOS (where `exe` is a `/nix/store/<hash>-<name>/bin/<name>` path) or on K3s (where the whole control plane is one `k3s server` process).

**Energy / cost tracking.** Scaphandre runs as a DaemonSet and reads CPU power directly from RAPL counters. Key metrics:

- `scaph_host_power_microwatts` -- total host power draw (uW), from RAPL PSYS on Skylake+ Intel
- `scaph_process_power_consumption_microwatts{exe, cmdline, pid}` -- per-process attribution

The bundled dashboard exposes:

- **Host power (RAPL PSYS)** -- live host reading, in W.
- **Sum of process power** -- `sum(scaph_process_power_consumption_microwatts) / 1e6`, should track the host reading.
- **Est. wall-plug power (x1.4)** -- RAPL PSYS multiplied by 1.4 to model PSU losses + components outside PSYS (fans, NVMe, NICs, board VRMs). The 1.4 factor combines (a) ~85 % typical 80 PLUS Bronze/Silver PSU efficiency (~1.18x) and (b) ~15-20 % additional draw from non-PSYS components, consistent with Khan et al., "How Much Power Does Your Server Consume? Estimating Wall Socket Power Using RAPL Measurements" (Springer, 2016) and "RAPL in Action" (ACM TOMPECS, 2018), which establish a strong but offset-bearing correlation between RAPL and wall-socket power. Calibrate against a smart plug for higher accuracy.
- **Est. daily energy at the wall** -- `avg_over_time(scaph_host_power_microwatts[24h]) * 1.4 * 24 / 1000 / 1e6` in kWh; multiply by your `EUR/kWh` to get monthly cost.
- Per-component power (k3s, prometheus, grafana, scaphandre, containerd, postgres) using `cmdline=~`-style regex.
- Top processes by current power.

Cost example (replace `0.20` by your `EUR/kWh` rate):

```promql
# Energy used over the dashboard time range, in kWh (host RAPL only)
sum_over_time(scaph_host_power_microwatts[$__range]) / 1e6 / 3600 / 1000

# Same, scaled to estimated wall-plug consumption
sum_over_time(scaph_host_power_microwatts[$__range]) / 1e6 / 3600 / 1000 * 1.4

# Estimated wall-plug cost over the range, EUR
sum_over_time(scaph_host_power_microwatts[$__range]) / 1e6 / 3600 / 1000 * 1.4 * 0.20
```

RAPL requires CPU support (Intel since Sandy Bridge / AMD since Zen). Scaphandre runs privileged to read MSRs.

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

### Adding media via Nextcloud

Jellyfin and Nextcloud share a `/data/media` hostPath volume. To upload films through Nextcloud's web UI:

1. In Nextcloud, go to **Apps** and enable **External storage support**.
2. Go to **Administration Settings > External storage**.
3. Add a new storage:
   - **Folder name**: `Media`
   - **External storage**: Local
   - **Configuration**: `/media`
   - **Available for**: All users (or restrict as needed)
4. The `Media` folder now appears in Nextcloud's file browser. Any file uploaded there is immediately visible to Jellyfin at `/media`.

## Post-bootstrap

This repository is the single source of truth. All changes go through git -- ArgoCD syncs automatically with pruning and self-healing enabled.

Manual operations (all runnable from your workstation with `KUBECONFIG` pointing at the cluster):

- **Vault unseal** (after pod restarts):
  ```bash
  UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-init.json)
  kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"
  # or: ./setup.sh 4
  ```
- **`terraform apply`** (when changing Vault or Authentik configuration). Port-forward first: `kubectl port-forward -n vault svc/vault 8200:8200` (or `authentik`).
- **Authentik user management** (via admin UI at auth.armleth.fr).
- **Traefik HelmChartConfig** (persisted in cluster by K3s, only needed once at bootstrap).
