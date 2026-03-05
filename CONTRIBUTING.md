# Contributing Guidelines

## Project Context
This is a GitOps infrastructure repository for a single-node K3s cluster. ArgoCD manages all applications declaratively from this repo. The stack includes Vault, Keycloak, CloudNativePG, cert-manager, and External Secrets Operator.

## Core Principles

### GitOps Standards
- Git is the single source of truth -- all changes MUST go through git commits
- All K8s resources must be declarative (no imperative kubectl commands in production)
- ArgoCD auto-syncs with pruning and self-healing enabled
- Never manually apply manifests (except bootstrap)

### Security Practices
- NEVER hardcode secrets in YAML or HCL files
- All secrets MUST be stored in Vault and synced via ExternalSecret CRs
- Use OIDC authentication via Keycloak for all services
- TLS certificates MUST be managed by cert-manager with Let's Encrypt
- All ingress endpoints MUST use HTTPS (TLS termination at Traefik)

### Kubernetes Manifests
- Use Kustomize for all K8s configurations (no Helm charts unless it is the recommanded way to install something in the official doc)
- Follow the existing directory structure: `k8s/apps/<service>/`
- Each service gets its own directory with: kustomization.yaml, deployment.yaml, service.yaml, ingress.yaml, etc.
- Use consistent naming: `<service>-<resource-type>` (e.g., `keycloak-deployment`, `vault-ingress`)
- Always specify namespaces explicitly in resources
- Use ArgoCD Application CRs in `k8s/apps/argocd/templates/` for new services

### Terraform Standards
- Separate Terraform configs by service: `terraform/vault/`, `terraform/keycloak/`
- Use explicit provider versions
- Store statefile locally (this is a homelab, not production)
- Always run `terraform plan` before `terraform apply`
- Document manual steps in README.md if Terraform can't handle them

### IngressRoute Configuration
- All external services need an IngressRoute in their app directory
- Use consistent hostname pattern: `<service>.armleth.fr`
- TLS must reference a cert-manager Certificate
- Example structure:
  ```yaml
  apiVersion: traefik.io/v1alpha1
  kind: IngressRoute
  metadata:
    name: <service>
    namespace: <namespace>
  spec:
    entryPoints: [websecure]
    routes:
      - match: Host(`<service>.armleth.fr`)
        kind: Rule
        services:
          - name: <service>
            port: <port>
    tls:
      secretName: <service>-tls-secret
  ```

### Certificate Management
- All TLS certs defined in `k8s/apps/cert-manager-config/certificates/<service>.yaml`
- Use `letsencrypt-prod` ClusterIssuer
- Certificate must be in the same namespace as the IngressRoute
- Add to `k8s/apps/cert-manager-config/kustomization.yaml` resources list

### ExternalSecret Pattern
- Define ExternalSecret in the service's namespace
- Reference the `vault-backend` ClusterSecretStore
- Path format: `secret/data/<service>/<key>`
- Mount as Kubernetes Secret with consistent naming: `<service>-<purpose>-secret`

### Documentation
- Update README.md when adding new services or changing bootstrap steps
- Include kubectl wait commands for readiness checks
- Document port-forward commands for local access
- Explain manual steps that can't be automated

### Changes to Existing Services
- Read the existing manifest files BEFORE making changes
- Maintain existing patterns and naming conventions
- Don't refactor code unnecessarily -- only change what's needed
- Test changes with `kubectl diff -k` or `kubectl apply --dry-run=server`
- For Terraform: always run `terraform plan` to preview changes

### Version Control
- Write clear, descriptive commit messages
- Use conventional commits format when possible: `feat:`, `fix:`, `docs:`, `refactor:`
- Don't commit sensitive files: vault-init.json, terraform.tfstate, kubeconfig

## Common Tasks

### Adding a New Service
1. Create directory: `k8s/apps/<service>/`
2. Create manifests: deployment.yaml, service.yaml, ingress.yaml, kustomization.yaml
3. If secrets needed: create ExternalSecret, ensure path exists in Vault
4. Create certificate: `k8s/apps/cert-manager-config/certificates/<service>.yaml`
5. Create ArgoCD Application: `k8s/apps/argocd/templates/<service>.yaml`
6. Update kustomization.yaml files as needed
7. Commit and push -- ArgoCD will sync automatically

### Adding a Secret to Vault
1. Port-forward to Vault: `kubectl port-forward -n vault svc/vault 8200:8200`
2. Set env vars: `export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=<token>`
3. Store secret: `vault kv put secret/<service> <key>=<value>`
4. Create ExternalSecret CR in K8s manifest

### Modifying Terraform Configs
1. Port-forward to the service if needed (Vault or Keycloak)
2. Set required environment variables
3. Run `terraform plan` to preview
4. Run `terraform apply` to execute
5. Update README.md if manual steps changed

## What NOT to Do
- Don't use Helm unless this is the recommended way to install it in the official documentation, or of it is too complex to do it otherwise.
- Don't create generic utilities or over-engineer solutions
- Don't add unnecessary error handling for impossible scenarios
- Don't refactor working code just to "improve" it
- Don't add comments explaining obvious YAML structure
- Don't create new documentation files without explicit request
- Don't use kubectl apply manually (except for bootstrap)
- Don't store secrets in git or pass them as arguments in manifests
