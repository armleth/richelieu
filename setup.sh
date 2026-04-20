#!/usr/bin/env bash
#
# Richelieu bootstrap script.
#
# Automates every step documented in README.md, from applying the ArgoCD
# bootstrap to configuring Authentik and Vault via Terraform.
#
# Steps that truly cannot be automated (recovery-link login, API-token
# creation in the Authentik UI, user/group creation, seeding the
# Lathibandolaise repo via an SSH-authenticated git clone) pause the script
# and prompt the operator to complete the action before continuing.
#
# Usage:
#   ./setup.sh            # run the full bootstrap
#   ./setup.sh <step>     # run from a specific step (e.g. ./setup.sh 5)
#
# Requirements on the local machine:
#   - kubectl pointing at the K3s cluster
#   - terraform
#   - jq
#   - openssl
#   - git
#   - ssh access to github.com (for the lathibandolaise clone on the host)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

VAULT_PF_PORT=8200
AUTHENTIK_PF_PORT=9000
VAULT_INIT_FILE="$REPO_ROOT/vault-init.json"

PF_PIDS=()

cleanup() {
    for pid in "${PF_PIDS[@]:-}"; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\n\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

pause() {
    printf '\n\033[1;35m[?]\033[0m %s\n' "$*"
    read -r -p "    Press ENTER when done (or Ctrl-C to abort)..." _
}

require() {
    command -v "$1" >/dev/null 2>&1 || die "missing required binary: $1"
}

port_forward() {
    # $1 namespace  $2 svc  $3 local:remote
    local ns="$1" svc="$2" mapping="$3"
    kubectl port-forward -n "$ns" "svc/$svc" "$mapping" >/dev/null 2>&1 &
    local pid=$!
    PF_PIDS+=("$pid")
    # wait a few seconds for the tunnel to come up
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if kill -0 "$pid" 2>/dev/null; then
            sleep 1
        else
            die "port-forward for svc/$svc failed"
        fi
    done
}

kill_port_forward() {
    # $1 pid to kill (if set)
    local pid="$1"
    [[ -z "$pid" ]] && return 0
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
}

########################################
# Step 0: prerequisites
########################################
step_prereqs() {
    log "Step 0: checking prerequisites"
    require kubectl
    require terraform
    require jq
    require openssl
    require git

    if ! kubectl cluster-info >/dev/null 2>&1; then
        die "kubectl cannot reach the cluster; point KUBECONFIG at the K3s node"
    fi
}

########################################
# Step 1: deploy ArgoCD (bootstrap)
########################################
step_argocd_bootstrap() {
    log "Step 1: applying ArgoCD bootstrap (app-of-apps)"
    kubectl apply -k k8s/bootstrap/ --server-side
}

########################################
# Step 2: wait for ArgoCD
########################################
step_wait_argocd() {
    log "Step 2: waiting for ArgoCD pods"
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
}

########################################
# Step 3: print ArgoCD initial admin password
########################################
step_argocd_password() {
    log "Step 3: ArgoCD initial admin password"
    local pw
    pw=$(kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath='{.data.password}' | base64 -d)
    printf '    ArgoCD admin password: %s\n' "$pw"
    printf '    Login at https://argocd.armleth.fr with user "admin".\n'
}

########################################
# Step 4: init + unseal Vault
########################################
step_vault_init_unseal() {
    log "Step 4: initialising and unsealing Vault"

    # Wait for vault pod to exist (Vault pods report NotReady until unsealed)
    log "  waiting for vault-0 pod to exist"
    for _ in $(seq 1 60); do
        if kubectl -n vault get pod vault-0 >/dev/null 2>&1; then
            break
        fi
        sleep 5
    done
    kubectl -n vault get pod vault-0 >/dev/null 2>&1 || die "vault-0 never appeared"

    # Wait until the pod is Running (sealed = NotReady, which is expected)
    log "  waiting for vault-0 to be Running"
    for _ in $(seq 1 60); do
        local phase
        phase=$(kubectl -n vault get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        [[ "$phase" == "Running" ]] && break
        sleep 5
    done

    if [[ -s "$VAULT_INIT_FILE" ]]; then
        warn "$VAULT_INIT_FILE already exists; skipping 'vault operator init'"
    else
        kubectl exec -n vault vault-0 -- vault operator init \
            -key-shares=1 -key-threshold=1 -format=json > "$VAULT_INIT_FILE"
        warn "Saved Vault init data to $VAULT_INIT_FILE -- store it securely and remove it from the repo host."
    fi

    local unseal_key
    unseal_key=$(jq -r '.unseal_keys_b64[0]' "$VAULT_INIT_FILE")
    # Unseal is idempotent; re-running after already unsealed is a no-op.
    kubectl exec -n vault vault-0 -- vault operator unseal "$unseal_key" >/dev/null
    log "  Vault unsealed"
}

########################################
# Step 5: configure Vault via terraform
########################################
step_vault_terraform() {
    log "Step 5: applying terraform/vault"

    port_forward vault vault "${VAULT_PF_PORT}:8200"
    local vault_pf_pid="${PF_PIDS[-1]}"

    export VAULT_ADDR="http://127.0.0.1:${VAULT_PF_PORT}"
    export VAULT_TOKEN
    VAULT_TOKEN=$(jq -r '.root_token' "$VAULT_INIT_FILE")

    (
        cd terraform/vault
        terraform init -upgrade
        terraform apply -auto-approve
    )

    kill_port_forward "$vault_pf_pid"
}

########################################
# Step 6: verify ESO ClusterSecretStore
########################################
step_verify_eso() {
    log "Step 6: verifying External Secrets ClusterSecretStore"
    # Allow some time for ArgoCD to sync the store resource
    for _ in $(seq 1 30); do
        if kubectl get clustersecretstore vault-backend >/dev/null 2>&1; then
            break
        fi
        sleep 5
    done
    kubectl get clustersecretstore vault-backend
}

########################################
# Step 7: store Authentik / Nextcloud / Lathibandolaise secrets in Vault
########################################
step_seed_secrets() {
    log "Step 7: seeding application secrets in Vault"

    printf '    A GitHub Personal Access Token is required for the Lathibandolaise GHCR pull secret.\n'
    printf '    It will be base64-encoded as "armleth:<PAT>".\n'
    local ghcr_pat
    read -r -s -p "    GitHub PAT for user 'armleth' (input hidden): " ghcr_pat
    echo
    [[ -z "$ghcr_pat" ]] && die "GHCR PAT is required"
    local ghcr_b64
    ghcr_b64=$(printf 'armleth:%s' "$ghcr_pat" | base64 -w0)

    # Run everything inside the vault-0 pod using its own vault CLI.
    # Passing VAULT_TOKEN via env so it never appears on a command line.
    kubectl exec -n vault vault-0 \
        --env VAULT_TOKEN="$VAULT_TOKEN" \
        --env GHCR_B64="$ghcr_b64" \
        -- sh -c '
            set -e
            vault kv put secret/authentik \
                admin-password="$(openssl rand -base64 24)" \
                secret-key="$(openssl rand -base64 60 | tr -d "\n")" \
                db-password="$(openssl rand -base64 24)"
            vault kv put secret/nextcloud \
                admin-password="$(openssl rand -base64 24)" \
                db-password="$(openssl rand -base64 24)"
            vault kv put secret/lathibandolaise \
                db-password="$(openssl rand -base64 24)" \
                ghcr-pat="$GHCR_B64"
        '
}

########################################
# Step 8: enable Traefik cross-namespace middleware
########################################
step_traefik_cross_namespace() {
    log "Step 8: enabling Traefik cross-namespace middleware"
    kubectl apply -f - <<'EOF'
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
EOF
    log "  waiting for Traefik rollout"
    kubectl rollout status deployment/traefik -n kube-system --timeout=120s
}

########################################
# Step 8b: patch CoreDNS for external torrent indexer DNS
########################################
step_coredns_patch() {
    log "Step 8b: patching CoreDNS to forward to 1.1.1.1 / 8.8.8.8"
    kubectl patch configmap coredns -n kube-system --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    hosts /etc/coredns/NodeHosts {\n      ttl 60\n      reload 15s\n      fallthrough\n    }\n    prometheus :9153\n    forward . 1.1.1.1 8.8.8.8\n    cache 30\n    loop\n    reload\n    loadbalance\n    import /etc/coredns/custom/*.override\n}\nimport /etc/coredns/custom/*.server\n"}}'
    kubectl rollout restart deployment coredns -n kube-system
    kubectl rollout status deployment/coredns -n kube-system --timeout=120s
}

########################################
# Step 9: host data directories (media + lathibandolaise)
########################################
step_host_dirs() {
    log "Step 9: host data directories"

    if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
        sudo mkdir -p /data/media/movies /data/media/tv
        sudo chown 1000:1000 /data/media/movies /data/media/tv
    else
        warn "Cannot sudo non-interactively; skipping /data/media setup."
        warn "Run manually on the host:"
        warn "    sudo mkdir -p /data/media/movies /data/media/tv"
        warn "    sudo chown 1000:1000 /data/media/movies /data/media/tv"
    fi

    if [[ ! -d /data/lathibandolaise ]]; then
        pause "Clone the Lathibandolaise repo on the host with your GitHub SSH key:
       sudo git clone git@github.com:armleth/lathibandolaise.git /data/lathibandolaise"
    else
        log "  /data/lathibandolaise already exists"
    fi
}

########################################
# Step 10: wait for Authentik, then apply terraform/authentik
########################################
step_authentik_terraform() {
    log "Step 10: waiting for Authentik server pod"
    kubectl wait --for=condition=Ready pods -l app=authentik-server -n authentik --timeout=600s

    log "  generating an Authentik recovery key for akadmin (valid 10 minutes)"
    kubectl exec -n authentik deployment/authentik-worker -- \
        ak create_recovery_key 10 akadmin

    pause "Open the recovery URL above in your browser, then in the Authentik UI:
       Settings > Tokens and App passwords > Create (intent: API)
       Copy the token for the next step."

    local authentik_token
    read -r -s -p "    Paste the Authentik API token (input hidden): " authentik_token
    echo
    [[ -z "$authentik_token" ]] && die "Authentik API token is required"

    port_forward authentik authentik-server "${AUTHENTIK_PF_PORT}:80"
    local authentik_pf_pid="${PF_PIDS[-1]}"

    export AUTHENTIK_URL="http://localhost:${AUTHENTIK_PF_PORT}"
    export AUTHENTIK_TOKEN="$authentik_token"

    local argocd_client_secret vault_client_secret
    (
        cd terraform/authentik
        terraform init -upgrade
        terraform apply -auto-approve
    )

    argocd_client_secret=$(cd terraform/authentik && terraform output -raw argocd_client_secret)
    vault_client_secret=$(cd terraform/authentik && terraform output -raw vault_client_secret)

    kill_port_forward "$authentik_pf_pid"

    log "  storing OIDC client secrets in Vault"
    # Vault port-forward (re-open; env VAULT_ADDR / VAULT_TOKEN still valid)
    port_forward vault vault "${VAULT_PF_PORT}:8200"
    local vault_pf_pid="${PF_PIDS[-1]}"

    kubectl exec -n vault vault-0 \
        --env VAULT_TOKEN="$VAULT_TOKEN" \
        --env ARGOCD_CLIENT_SECRET="$argocd_client_secret" \
        -- vault kv put secret/argocd oidc-client-secret="$ARGOCD_CLIENT_SECRET"

    kubectl exec -n vault vault-0 \
        --env VAULT_TOKEN="$VAULT_TOKEN" \
        -- vault kv get -field=oidc-client-secret secret/argocd >/dev/null

    log "  re-applying terraform/vault with the Authentik OIDC client secret"
    (
        cd terraform/vault
        terraform apply -auto-approve \
            -var="vault_oidc_client_secret=$vault_client_secret"
    )

    kill_port_forward "$vault_pf_pid"

    log "  restarting ArgoCD server to pick up the new OIDC secret"
    kubectl rollout restart deployment argocd-server -n argocd
    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
}

########################################
# Step 11: final manual follow-ups
########################################
step_final_instructions() {
    cat <<EOF

============================================================
Bootstrap complete.

Manual follow-ups (cannot be automated):

 1. Log in to https://auth.armleth.fr using a recovery link
    (generate another with:
     kubectl exec -n authentik deployment/authentik-worker \\
       -- ak create_recovery_key 10 akadmin
    ).
    - Directory > Users: create your user
    - Directory > Groups: add the user to the groups they need
      (managed via terraform/authentik/groups.tf):
        admin  -- full access (all services)
        bbox   -- Bbox (for non-admins)
        dev    -- Code Server, Lathibandolaise test/prod, DbGate
        media  -- Radarr, Sonarr, Prowlarr, qBittorrent, Flood

    SSO is then available for ArgoCD, Vault, Bbox, Homepage, Code Server,
    Lathibandolaise test/prod, DbGate (db.lathibandolaise.dev.armleth.fr),
    and the media stack.

 2. Log in to ArgoCD (https://argocd.armleth.fr) via Authentik SSO
    and verify every Application syncs Healthy.

 3. Media stack post-deploy wiring (Prowlarr/Radarr/Sonarr/qBittorrent/
    Flood/Jellyfin) -- see "Media stack > Service wiring" in README.md.

 4. Enable Jellyfin Intel QSV transcoding settings -- see
    "Jellyfin hardware acceleration" in README.md.

 5. Nextcloud: enable External storage support, mount /media as the
    "Media" folder -- see "Adding media via Nextcloud" in README.md.

Remember:
 - Vault must be re-unsealed after every pod restart:
     UNSEAL_KEY=\$(jq -r '.unseal_keys_b64[0]' $VAULT_INIT_FILE)
     kubectl exec -n vault vault-0 -- vault operator unseal "\$UNSEAL_KEY"
 - $VAULT_INIT_FILE contains the root token and unseal key.
   Move it off the cluster host and keep it somewhere safe.
============================================================
EOF
}

########################################
# Driver
########################################
ALL_STEPS=(
    step_prereqs
    step_argocd_bootstrap
    step_wait_argocd
    step_argocd_password
    step_vault_init_unseal
    step_vault_terraform
    step_verify_eso
    step_seed_secrets
    step_traefik_cross_namespace
    step_coredns_patch
    step_host_dirs
    step_authentik_terraform
    step_final_instructions
)

main() {
    local start="${1:-0}"
    local i=0
    for fn in "${ALL_STEPS[@]}"; do
        if (( i >= start )); then
            "$fn"
        fi
        i=$((i+1))
    done
}

main "$@"
