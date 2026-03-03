variable "vault_oidc_client_secret" {
  type        = string
  sensitive   = true
  description = "OIDC client secret for Vault from Keycloak"
  default     = ""
}

resource "vault_jwt_auth_backend" "keycloak" {
  count = var.vault_oidc_client_secret != "" ? 1 : 0

  type               = "oidc"
  path               = "oidc"
  oidc_discovery_url = "https://auth.armleth.fr/realms/infrastructure"
  oidc_client_id     = "vault"
  oidc_client_secret = var.vault_oidc_client_secret
  default_role       = "default"

  tune {
    listing_visibility = "unauth"
  }
}

resource "vault_jwt_auth_backend_role" "default" {
  count = var.vault_oidc_client_secret != "" ? 1 : 0

  backend       = vault_jwt_auth_backend.keycloak[0].path
  role_name     = "default"
  role_type     = "oidc"
  token_ttl     = 3600
  token_max_ttl = 7200

  bound_audiences = ["vault"]
  user_claim      = "sub"
  groups_claim    = "groups"
  claim_mappings = {
    preferred_username = "username"
    email              = "email"
  }

  allowed_redirect_uris = [
    "https://vault.armleth.fr/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]

  token_policies = ["default"]
}

resource "vault_identity_group" "admins" {
  count = var.vault_oidc_client_secret != "" ? 1 : 0

  name     = "admins"
  type     = "external"
  policies = [vault_policy.admin.name]
}

resource "vault_identity_group_alias" "admins_keycloak" {
  count = var.vault_oidc_client_secret != "" ? 1 : 0

  name           = "admins"
  mount_accessor = vault_jwt_auth_backend.keycloak[0].accessor
  canonical_id   = vault_identity_group.admins[0].id
}
