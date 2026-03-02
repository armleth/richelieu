resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets-vault-auth"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = [vault_policy.external_secrets.name]
  token_ttl                        = 3600
}
