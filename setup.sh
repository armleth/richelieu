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
# This script is designed to run from your workstation, not on the K3s
# node itself. Every cluster operation goes through kubectl / port-forward,
# so your workstation only needs network access to the API server on 6443.
#
# The only host-level operations are creating /data/media and cloning
# /data/lathibandolaise on the node; those are performed over SSH when
# the RICHELIEU_SSH_HOST environment variable is set (e.g.
# "armleth@richelieu.lan"). Without it, the script prints the commands
# to run manually on the node.
#
# Usage:
#   # kubectl already configured via ~/.kube/config pointing at the remote
#   # K3s cluster (see README "Workstation prerequisites").
#   export RICHELIEU_SSH_HOST=armleth@<server>   # optional but recommended
#   ./setup.sh                                   # full bootstrap
#   ./setup.sh <step>                            # resume from a specific step
#
# Output: vault-init.json is written to the repo root on the workstation
# (already in .gitignore). Keep it safe -- it contains the Vault root
# token and unseal key.
#
# Requirements on the workstation:
#   - kubectl (~/.kube/config pointing at the remote K3s cluster)
#   - terraform
#   - jq
#   - openssl
#   - git
#   - ssh, if RICHELIEU_SSH_HOST is set

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

VAULT_PF_PORT=8200
AUTHENTIK_PF_PORT=9000
VAULT_INIT_FILE="$REPO_ROOT/vault-init.json"

# If set, host-level commands (mkdir /data/media, git clone
# /data/lathibandolaise) run over SSH against this host instead of
# prompting the operator to do them manually.
SSH_HOST="${RICHELIEU_SSH_HOST:-}"

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
    # The bootstrap kustomization contains CRDs AND custom resources that use
    # them, so a single apply cannot converge:
    #   - ArgoCD's install.yaml creates the Application CRD; Application CRs
    #     in templates/ are rejected in the same pass with
    #     "no matches for kind Application" (discovery-cache race).
    #   - argocd-oidc-secret is an ExternalSecret, but the external-secrets
    #     operator CRDs are installed by ArgoCD itself after syncing the
    #     external-secrets Application (takes 1-3 minutes).
    # Retry until every resource is accepted. kubectl apply exits non-zero
    # when any resource fails, so we loop until a clean run.
    #
    # --force-conflicts: ArgoCD will start reconciling its own resources
    # mid-bootstrap and grab field ownership; git is the source of truth,
    # so our apply must win those conflicts.
    #
    # --field-manager=argocd-controller: write every field under the same
    # SSA field manager ArgoCD itself uses. Without this, kubectl's default
    # manager ("kubectl") ends up co-owning the same fields as
    # argocd-controller, which is a permanent SSA conflict source. In that
    # state, ArgoCD's self-heal retry logic injects
    # `syncStrategy.hook.force: true` into the sync op, which translates to
    # kubectl's --force flag -- incompatible with --server-side -- and the
    # parent argocd app gets stuck OutOfSync in an infinite retry loop
    # ("error validating options: --force cannot be used with --server-side").
    # This primarily bites Applications that carry an
    # `argocd.argoproj.io/sync-wave` annotation (cert-manager,
    # cert-manager-config, authentik), because v3.3.2 routes later-wave
    # applies through a kubectl-subprocess path that actually emits --force.
    local max_wait=600         # 10 minutes
    local interval=10
    local elapsed=0
    local log_file
    log_file=$(mktemp)
    # Retryable errors during convergence:
    #   - "no matches for kind ..." / "ensure CRDs are installed first"
    #       CRDs haven't been registered yet (discovery-cache race).
    #   - "could not find the requested resource"
    #       Same family of errors from older kubectl versions.
    #   - 'no endpoints available for service "..."'
    #       Admission webhooks not yet ready (external-secrets, cert-manager,
    #       etc. are still rolling out).
    local retryable='(ensure CRDs are installed first|no matches for kind|could not find the requested resource|no endpoints available for service|failed calling webhook)'
    while (( elapsed < max_wait )); do
        if kubectl apply -k k8s/bootstrap/ --server-side --force-conflicts \
                --field-manager=argocd-controller >"$log_file" 2>&1; then
            cat "$log_file"
            rm -f "$log_file"
            log "  bootstrap applied cleanly after ${elapsed}s"
            return 0
        fi
        # Only tolerate the known transient errors; anything else (RBAC,
        # quota, typo, ...) should fail loudly.
        if ! grep -qE "$retryable" "$log_file"; then
            cat "$log_file" >&2
            rm -f "$log_file"
            die "bootstrap apply failed for reasons other than missing CRDs / unready webhooks (see above)"
        fi
        local crd_missing webhook_down
        crd_missing=$(grep -c "no matches for kind" "$log_file" || true)
        webhook_down=$(grep -Ec 'no endpoints available|failed calling webhook' "$log_file" || true)
        log "  still converging (CRD-missing: ${crd_missing}, webhook-down: ${webhook_down}); retrying in ${interval}s (elapsed ${elapsed}s)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    cat "$log_file" >&2
    rm -f "$log_file"
    die "bootstrap apply never converged after ${max_wait}s"
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
# Ensure VAULT_TOKEN and VAULT_ADDR are set (e.g. when resuming the script
# from a later step, in which case step_vault_init_unseal didn't run).
# The terraform vault provider silently hangs (retrying TLS against a
# plain-HTTP port-forward) when VAULT_ADDR is missing.
########################################
ensure_vault_token() {
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        [[ -s "$VAULT_INIT_FILE" ]] || die "VAULT_TOKEN unset and $VAULT_INIT_FILE is missing; run from an earlier step."
        export VAULT_TOKEN
        VAULT_TOKEN=$(jq -r '.root_token' "$VAULT_INIT_FILE")
    fi
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        export VAULT_ADDR="http://127.0.0.1:${VAULT_PF_PORT}"
    fi
}

########################################
# Step 7: store Authentik / Nextcloud / Lathibandolaise secrets in Vault
########################################
step_seed_secrets() {
    log "Step 7: seeding application secrets in Vault"
    ensure_vault_token

    printf '    A GitHub Personal Access Token is required for the Lathibandolaise GHCR pull secret.\n'
    printf '    It will be base64-encoded as "armleth:<PAT>".\n'
    local ghcr_pat
    read -r -s -p "    GitHub PAT for user 'armleth' (input hidden): " ghcr_pat
    echo
    [[ -z "$ghcr_pat" ]] && die "GHCR PAT is required"
    local ghcr_b64
    ghcr_b64=$(printf 'armleth:%s' "$ghcr_pat" | base64 -w0)

    # Generate random values on the workstation (openssl may not exist in
    # the Vault/OpenBao container image). Pass everything to the pod as env
    # vars so no secret ever appears on a command line.
    local authentik_admin_password authentik_secret_key authentik_db_password
    local nextcloud_admin_password nextcloud_db_password
    local lathibandolaise_db_password
    authentik_admin_password=$(openssl rand -base64 24)
    authentik_secret_key=$(openssl rand -base64 60 | tr -d '\n')
    authentik_db_password=$(openssl rand -base64 24)
    nextcloud_admin_password=$(openssl rand -base64 24)
    nextcloud_db_password=$(openssl rand -base64 24)
    lathibandolaise_db_password=$(openssl rand -base64 24)

    kubectl exec -n vault vault-0 \
        -- env \
            VAULT_TOKEN="$VAULT_TOKEN" \
            AUTHENTIK_ADMIN_PASSWORD="$authentik_admin_password" \
            AUTHENTIK_SECRET_KEY="$authentik_secret_key" \
            AUTHENTIK_DB_PASSWORD="$authentik_db_password" \
            NEXTCLOUD_ADMIN_PASSWORD="$nextcloud_admin_password" \
            NEXTCLOUD_DB_PASSWORD="$nextcloud_db_password" \
            LATHIBANDOLAISE_DB_PASSWORD="$lathibandolaise_db_password" \
            GHCR_B64="$ghcr_b64" \
        sh -c '
            set -e
            vault kv put secret/authentik \
                admin-password="$AUTHENTIK_ADMIN_PASSWORD" \
                secret-key="$AUTHENTIK_SECRET_KEY" \
                db-password="$AUTHENTIK_DB_PASSWORD"
            vault kv put secret/nextcloud \
                admin-password="$NEXTCLOUD_ADMIN_PASSWORD" \
                db-password="$NEXTCLOUD_DB_PASSWORD"
            vault kv put secret/lathibandolaise \
                db-password="$LATHIBANDOLAISE_DB_PASSWORD" \
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
    log "Step 9: host data directories on the K3s node"

    if [[ -n "$SSH_HOST" ]]; then
        log "  using SSH target: $SSH_HOST"

        # -t forces a TTY on the remote so sudo can prompt for a password
        # when passwordless sudo isn't configured. Harmless otherwise.
        ssh -t "$SSH_HOST" 'sudo mkdir -p /data/media/movies /data/media/tv \
            && sudo chown 1000:1000 /data/media/movies /data/media/tv'

        if ssh "$SSH_HOST" 'test -d /data/lathibandolaise/.git'; then
            log "  /data/lathibandolaise already exists"
        else
            log "  cloning Lathibandolaise via SSH agent forwarding"
            if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l >/dev/null 2>&1; then
                warn "No SSH agent / identity detected on this workstation."
                warn "Start one and add your GitHub key before continuing, e.g.:"
                warn "    eval \"\$(ssh-agent -s)\""
                warn "    ssh-add ~/.ssh/id_ed25519"
                pause "Press ENTER once your agent has the GitHub key loaded."
            fi

            # -A forwards the local SSH agent so git-over-SSH on the node can
            # authenticate to GitHub with your workstation key (no key ever
            # lands on the server). We pre-create the target directory owned
            # by the SSH user so the clone doesn't need sudo (which would
            # strip SSH_AUTH_SOCK).
            ssh -A -t "$SSH_HOST" '
                set -e
                sudo mkdir -p /data/lathibandolaise
                sudo chown "$(id -u):$(id -g)" /data/lathibandolaise
                mkdir -p ~/.ssh
                touch ~/.ssh/known_hosts
                ssh-keyscan -H github.com 2>/dev/null >> ~/.ssh/known_hosts
                sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts
                git clone git@github.com:armleth/lathibandolaise.git /data/lathibandolaise
            '
        fi
    else
        warn "RICHELIEU_SSH_HOST is not set; cannot run host-level commands."
        warn "Open another terminal, SSH into the K3s node, and run:"
        warn "    sudo mkdir -p /data/media/movies /data/media/tv"
        warn "    sudo chown 1000:1000 /data/media/movies /data/media/tv"
        warn "    sudo git clone git@github.com:armleth/lathibandolaise.git /data/lathibandolaise"
        pause "Run the commands above on the K3s node, then press ENTER to continue."
    fi
}

########################################
# Step 10: wait for Authentik, then apply terraform/authentik
########################################
step_authentik_terraform() {
    log "Step 10: waiting for Authentik server pod"
    ensure_vault_token
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

        # The "authentik Embedded Outpost" is auto-created by Authentik
        # itself on startup, so our resource declaration would collide
        # with it. If it isn't already in state, import it first.
        if ! terraform state list 2>/dev/null | grep -q '^authentik_outpost\.embedded$'; then
            local embedded_pk
            embedded_pk=$(curl -sS \
                -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
                "${AUTHENTIK_URL}/api/v3/outposts/instances/?name_iexact=authentik+Embedded+Outpost" \
                | python3 -c 'import json,sys; r=json.load(sys.stdin)["results"]; print(r[0]["pk"] if r else "")')
            if [[ -n "$embedded_pk" ]]; then
                log "  importing existing Embedded Outpost ($embedded_pk) into terraform state"
                terraform import authentik_outpost.embedded "$embedded_pk"
            fi
        fi

        # -parallelism=1 avoids hammering Authentik's API server with
        # concurrent requests, which otherwise triggers 500/405 responses
        # when the DB / server is under memory pressure.
        terraform apply -auto-approve -parallelism=1
    )

    argocd_client_secret=$(cd terraform/authentik && terraform output -raw argocd_client_secret)
    vault_client_secret=$(cd terraform/authentik && terraform output -raw vault_client_secret)

    kill_port_forward "$authentik_pf_pid"

    log "  storing OIDC client secrets in Vault"
    # Vault port-forward (re-open; env VAULT_ADDR / VAULT_TOKEN still valid)
    port_forward vault vault "${VAULT_PF_PORT}:8200"
    local vault_pf_pid="${PF_PIDS[-1]}"

    kubectl exec -n vault vault-0 \
        -- env VAULT_TOKEN="$VAULT_TOKEN" ARGOCD_CLIENT_SECRET="$argocd_client_secret" \
        sh -c 'vault kv put secret/argocd oidc-client-secret="$ARGOCD_CLIENT_SECRET"'

    kubectl exec -n vault vault-0 \
        -- env VAULT_TOKEN="$VAULT_TOKEN" \
        vault kv get -field=oidc-client-secret secret/argocd >/dev/null

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
 - Vault must be re-unsealed after every pod restart. From this
   workstation (KUBECONFIG still pointing at the cluster):
     UNSEAL_KEY=\$(jq -r '.unseal_keys_b64[0]' $VAULT_INIT_FILE)
     kubectl exec -n vault vault-0 -- vault operator unseal "\$UNSEAL_KEY"
   Or: ./setup.sh 4   (re-runs just the init/unseal step)
 - $VAULT_INIT_FILE contains the root token and unseal key.
   It lives on this workstation, NOT on the K3s node -- keep it safe
   (password manager, encrypted backup, etc.) and out of git.
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
